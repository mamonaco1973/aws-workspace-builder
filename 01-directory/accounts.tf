# Generate a random password for the Active Directory (AD) Administrator
resource "random_password" "admin_password" {
  length           = 24    # Set password length to 24 characters
  special          = true  # Include special characters in the password
  override_special = "_-." # Limit special characters to this set
}

# Create an AWS Secrets Manager secret to store AD Admin credentials
resource "aws_secretsmanager_secret" "admin_secret" {
  name        = "admin_ad_credentials" # Name of the secret
  description = "AD Admin Credentials" # Description for reference

  lifecycle {
    prevent_destroy = false # Allow secret deletion if necessary
  }
}

# Store the admin credentials in AWS Secrets Manager with a versioned secret
resource "aws_secretsmanager_secret_version" "admin_secret_version" {
  secret_id = aws_secretsmanager_secret.admin_secret.id # Reference the secret
  secret_string = jsonencode({
    username = "${var.netbios}\\Admin"               # AD username
    password = random_password.admin_password.result # Generated password
  })
}

