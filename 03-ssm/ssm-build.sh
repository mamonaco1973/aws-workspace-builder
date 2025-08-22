#!/bin/bash

# Get activation_id from Secrets Manager
ACTIVATION_ID=$(aws secretsmanager get-secret-value \
  --secret-id hybrid_activation \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r '.activation_id' | xargs)

# If activation_id is empty, bail
if [[ -z "$ACTIVATION_ID" ]]; then
  echo "ERROR: activation_id is empty from Secrets Manager"
  exit 1
fi

echo "NOTE: Looking for ActivationId: $ACTIVATION_ID"

MI_ID=$(aws ssm describe-instance-information \
    --region us-east-1 \
    --query "InstanceInformationList[?ActivationId=='${ACTIVATION_ID}' && PingStatus=='Online'].InstanceId" \
    --output text | xargs)

# If mi_id is empty, bail
if [[ -z "$MI_ID" ]]; then
  echo "ERROR: mi_id is empty from SSM"
  exit 1
fi


echo "NOTE: Using Managed Instance ID: $MI_ID"

./ssm-execute.sh "$MI_ID" "chrome.json" 