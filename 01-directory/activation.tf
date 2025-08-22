# ------------------------------------------------------------------------------
# Create IAM Role for Hybrid Instances
# ------------------------------------------------------------------------------

resource "aws_iam_role" "ssm_hybrid_instance_role" {
  name = "ssm-hybrid-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "ssm.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ssm_hybrid_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# Create SSM Hybrid Activation
# ------------------------------------------------------------------------------

resource "aws_ssm_activation" "hybrid_activation" {
  name               = "HybridActivation"
  description        = "Activation for registering on-prem or non-EC2 machines"
  iam_role           = aws_iam_role.ssm_hybrid_instance_role.name
  registration_limit = 10   # Number of servers you can register with this activation
  expiration_date    = timeadd(timestamp(), "720h") # optional, 30 days from now
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "activation_id" {
  value = aws_ssm_activation.hybrid_activation.id
}

output "activation_code" {
  value = aws_ssm_activation.hybrid_activation.activation_code
}
