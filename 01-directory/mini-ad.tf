# ==================================================================================================
# Fetch the Canonical-published Ubuntu 24.04 AMI ID from AWS Systems Manager Parameter Store
# This path is maintained by Canonical; it always points at the current stable AMI for 24.04 (amd64, HVM, gp3)
# ==================================================================================================
data "aws_ssm_parameter" "ubuntu_24_04" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ==================================================================================================
# Resolve the full AMI object using the ID returned by SSM
# - Restrict owner to Canonical to avoid spoofed AMIs
# - Filter by the exact image-id pulled above
# - most_recent is kept true as a guard when multiple matches exist in a region
# ==================================================================================================
data "aws_ami" "ubuntu_ami" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "image-id"
    values = [data.aws_ssm_parameter.ubuntu_24_04.value]
  }
}

# ==================================================================================================
# EC2 instance: Ubuntu 24.04 for Samba-based mini-AD DC
# - Private subnet only (no public IP)
# - IAM instance profile enables SSM connectivity (Session Manager, etc.)
# - User data renders from a template with domain settings and admin secrets
# ==================================================================================================
resource "aws_instance" "mini_ad_dc_instance" {
  ami                    = data.aws_ami.ubuntu_ami.id
  instance_type          = "t3.small"                    # Small, adequate for lab AD DC; scale up for real loads
  subnet_id              = aws_subnet.ad-subnet.id       # Place in private subnet
  vpc_security_group_ids = [aws_security_group.ad_sg.id] # Open required AD/DC ports per your SG

  associate_public_ip_address = false # Private-only; reach it via SSM/bastion/VPN

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = templatefile("./scripts/mini-ad.sh.template", {
    HOSTNAME_DC        = "ad1"
    DNS_ZONE           = var.dns_zone
    REALM              = var.realm
    NETBIOS            = var.netbios
    ADMINISTRATOR_PASS = random_password.admin_password.result
    ADMIN_USER_PASS    = random_password.admin_password.result
    USERS_JSON         = local.users_json
    ACTIVATION_CODE    = aws_ssm_activation.hybrid_activation.activation_code
  })

  tags = {
    Name = "mini-ad-dc-${lower(var.netbios)}"
  }

  # Ensure NAT + route association exist before bootstrapping (for package repos, etc.)
  depends_on = [
    aws_nat_gateway.ad_nat,
    aws_route_table_association.rt_assoc_ad_private
  ]
}

# ==================================================================================================
# DHCP options for the VPC to direct instances to this DC for DNS
# - domain_name: sets the search suffix (your AD DNS zone)
# - domain_name_servers: points DHCP clients at the DC’s private IP for lookups
# ==================================================================================================
resource "aws_vpc_dhcp_options" "mini_ad_dns" {
  domain_name         = var.dns_zone
  domain_name_servers = [aws_instance.mini_ad_dc_instance.private_ip]

  tags = {
    Name = "mini-ad-dns"
  }
}

# ==================================================================================================
# Delay to allow the DC to finish provisioning (Samba/DNS up) before associating DHCP options
# Adjust duration to your bootstrap time; 180s is a conservative lab default
# ==================================================================================================
resource "time_sleep" "wait_for_mini_ad" {
  depends_on      = [aws_instance.mini_ad_dc_instance]
  create_duration = "180s"
}

# ==================================================================================================
# Associate the custom DHCP options with the VPC once the DC is up
# This causes new DHCP leases to prefer the DC for DNS resolution within the VPC
# ==================================================================================================
resource "aws_vpc_dhcp_options_association" "mini_ad_dns_assoc" {
  vpc_id          = aws_vpc.ad-vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.mini_ad_dns.id
  depends_on      = [time_sleep.wait_for_mini_ad]
}


# -------------------------------------------------------------------
# Local variable: users_json
# - Renders a JSON template file (`users.json.template`)
# - Injects dynamically generated random passwords into the template
# - Produces a single JSON blob you can pass into VM bootstrap
# -------------------------------------------------------------------
locals {
  users_json = templatefile("./scripts/users.json.template", {
    USER_BASE_DN      = var.user_base_dn                      # User base DN for LDAP
    DNS_ZONE          = var.dns_zone                          # DNS zone (e.g., mcloud.mikecloud.com)
    REALM             = var.realm                             # Kerberos realm
    NETBIOS           = var.netbios                           # NetBIOS name
    sysadmin_password = random_password.admin_password.result # Insert sysadmin's random password

  })
}

