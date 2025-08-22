# =====================================================================================
# AD Connector stub for AWS Directory Service
# Purpose:
#   - Bridge AWS services (like WorkSpaces, RDS SQL Server, FSx) to your mini-AD
#   - Uses your Samba-based DC running in EC2 as the backend directory
# =====================================================================================

# -----------------------------------------------------------------------------
# Data source to resolve your Mini-AD DC instance by tag
# -----------------------------------------------------------------------------
data "aws_instance" "mini_ad_dc" {
  filter {
    name   = "tag:Name"
    values = ["mini-ad-dc-${lower(var.netbios)}"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# ==============================================================================
# Data block to retrieve AD Admin credentials from Secrets Manager
# ==============================================================================

# Get the latest version of the secret value
data "aws_secretsmanager_secret_version" "admin_secret_version" {
  secret_id = data.aws_secretsmanager_secret.admin_secret.id
}

# Decode JSON string into usable attributes
locals {
  admin_secret = jsondecode(data.aws_secretsmanager_secret_version.admin_secret_version.secret_string)
}

# -----------------------------------------------------------------------------
# AD Connector
# -----------------------------------------------------------------------------
resource "aws_directory_service_directory" "mini_ad_connector" {
  name     = "${var.dns_zone}"                # must match your Samba AD DNS zone
  password = local.admin_secret.password      # pulled from Secrets Manager in prod
  size     = "Small"
  type     = "ADConnector"
  short_name  = var.netbios 

  connect_settings {
    customer_dns_ips  = [data.aws_instance.mini_ad_dc.private_ip] # your Samba DC IP
    customer_username = "Admin"                                   # or Admin user you set up
    subnet_ids        = [
      data.aws_subnet.vm_subnet_1.id,
      data.aws_subnet.vm_subnet_2.id
    ] 
    vpc_id            = data.aws_vpc.ad_vpc.id
  }
}
