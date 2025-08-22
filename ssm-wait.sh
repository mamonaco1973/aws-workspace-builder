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

# Poll for MI_ID tied to this activation and Online
MAX_ATTEMPTS=120   # 1 hour with 30s interval
INTERVAL=30
COUNT=0
MI_ID=""

while [[ -z "$MI_ID" ]]; do
  MI_ID=$(aws ssm describe-instance-information \
    --region us-east-1 \
    --query "InstanceInformationList[?ActivationId=='${ACTIVATION_ID}' && PingStatus=='Online'].InstanceId" \
    --output text | xargs)

  if [[ -n "$MI_ID" ]]; then
    echo "NOTE: Managed Instance is Online: $MI_ID"
    break
  fi

  if (( COUNT >= MAX_ATTEMPTS )); then
    echo "ERROR: Timed out waiting for managed instance with ActivationId=$ACTIVATION_ID to come Online"
    exit 1
  fi

  echo "WARNING: Waiting for Managed Instance to register + come Online... attempt $((COUNT+1))/$MAX_ATTEMPTS"
  sleep $INTERVAL
  COUNT=$((COUNT+1))
done

