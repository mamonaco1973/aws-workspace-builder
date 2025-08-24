#!/bin/bash
# --------------------------------------------------------------------------------------------------
# Description:
#   End-to-end automation script for provisioning and validating an AWS-backed
#   Workspace environment. The workflow is executed in sequential phases:
#
#     Phase 1: Deploy Active Directory (AD) instance.
#     Phase 2: Deploy Workspace resources dependent on AD.
#     Phase 3: Wait for SSM Agent activation on the Workspace.
#     Phase 4: Run post-provisioning installs via SSM.
#     Phase 5: Capture a golden image and create a Workspace bundle.
#     Phase 6: Run final validation checks.
#
# Key Features:
#   - Performs environment pre-checks before provisioning.
#   - Uses Terraform modules for infrastructure deployment.
#   - Waits for AD initialization and SSM agent readiness.
#   - Automates software installation on the Workspace.
#   - Produces a validated, bundled image for reuse.
#
# Requirements:
#   - AWS CLI configured with valid credentials/permissions.
#   - Terraform installed and available in PATH.
#   - Scripts present in working directory:
#       * check_env.sh    (pre-flight validation)
#       * ssm-wait.sh     (poll for SSM activation)
#       * ssm-build.sh    (SSM-driven installs)
#       * build_bundle.sh (image + bundle creation)
#       * validate.sh     (final verification)
# --------------------------------------------------------------------------------------------------

# --------------------------------------------------------------------------------------------------
# Global Configuration
# --------------------------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"   # Target AWS region
DNS_ZONE="mcloud.mikecloud.com"         # AD DNS zone / domain name

# --------------------------------------------------------------------------------------------------
# Environment Pre-Check
# --------------------------------------------------------------------------------------------------
echo "NOTE: Running environment validation..."
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

# --------------------------------------------------------------------------------------------------
# Phase 1: Deploy Active Directory
# --------------------------------------------------------------------------------------------------
echo "NOTE: Deploying Active Directory..."
cd 01-directory || { echo "ERROR: Directory 01-directory not found"; exit 1; }

terraform init
terraform apply -auto-approve  

cd .. || exit

# --------------------------------------------------------------------------------------------------
# Phase 2: Deploy Workspace
# --------------------------------------------------------------------------------------------------
echo "NOTE: Deploying Workspace..."
cd 02-workspace || { echo "ERROR: Directory 02-workspace not found"; exit 1; }

terraform init
terraform apply -auto-approve  

cd .. || exit

# --------------------------------------------------------------------------------------------------
# Phase 3: Wait for SSM Agent Activation
# --------------------------------------------------------------------------------------------------
./ssm-wait.sh

# --------------------------------------------------------------------------------------------------
# Phase 4: Run Post-Provisioning Installs
# --------------------------------------------------------------------------------------------------
cd 03-ssm || { echo "ERROR: Directory 03-ssm not found"; exit 1; }
./ssm-build.sh
cd ..

# --------------------------------------------------------------------------------------------------
# Phase 5: Capture Image & Create Bundle
# --------------------------------------------------------------------------------------------------
./build_bundle.sh

# --------------------------------------------------------------------------------------------------
# Phase 6: Run Final Validation
# --------------------------------------------------------------------------------------------------
./validate.sh
