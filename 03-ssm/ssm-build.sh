#!/bin/bash
# =====================================================================
# Script: ssm-build
# Purpose:
#   - Retrieve an SSM hybrid activation ID from AWS Secrets Manager.
#   - Map the activation ID to a managed instance (MI_ID).
#   - Execute predefined SSM documents (Chrome, Notepad++) 
#     against the managed instance.
#
# Usage:
#   ./ssm-build.sh
#
# Exit Codes:
#   1 - Activation ID not found in Secrets Manager.
#   1 - Managed Instance ID not found in SSM.
#
# Notes:
#   - Assumes AWS CLI, jq, and ssm-execute.sh are available.
#   - Region is hardcoded to us-east-1.
#   - Execution will stop immediately on any command failure (set -e).
# =====================================================================


# --- Retrieve Activation ID ------------------------------------------
# Fetch activation_id from AWS Secrets Manager and strip whitespace.
ACTIVATION_ID=$(aws secretsmanager get-secret-value \
  --secret-id hybrid_activation \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r '.activation_id' | xargs)

# Validate that the activation_id is not empty.
if [[ -z "$ACTIVATION_ID" ]]; then
  echo "ERROR: activation_id is empty from Secrets Manager"
  exit 1
fi

echo "NOTE: Looking for ActivationId: $ACTIVATION_ID"


# --- Resolve Managed Instance ID -------------------------------------
# Query SSM for an instance bound to the activation_id and currently Online.
MI_ID=$(aws ssm describe-instance-information \
    --region us-east-1 \
    --query "InstanceInformationList[?ActivationId=='${ACTIVATION_ID}' && PingStatus=='Online'].InstanceId" \
    --output text | xargs)

# Validate that a managed instance was found.
if [[ -z "$MI_ID" ]]; then
  echo "ERROR: mi_id is empty from SSM"
  exit 1
fi

echo "NOTE: Using Managed Instance ID: $MI_ID"


# --- Execute SSM Documents -------------------------------------------
# Enable "exit immediately" on error to ensure reliability.
set -e

# Execute AD tools SSM document.

./ssm-execute.sh "$MI_ID" "adtools.json"

# Reboot after this step and wait for it to come back online

./wsreboot.sh

# Execute Chrome installation SSM document.
./ssm-execute.sh "$MI_ID" "chrome.json"

# Execute Notepad++ installation SSM document.
./ssm-execute.sh "$MI_ID" "npp.json"
