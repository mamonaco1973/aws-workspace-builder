#!/bin/bash
# =====================================================================
# Script: ssm-execute
# Purpose:
#   - Execute a custom SSM document against a managed instance.
#   - Takes MI_ID (Managed Instance ID) and JSON file as parameters.
# Usage:
#   ./ssm-execute mi-0123456789abcdef my-doc.json
# =====================================================================

# --- Input validation ---
if [ $# -ne 2 ]; then
  echo "Usage: $0 <MI_ID> <SSM_JSON_FILE>"
  exit 1
fi

MI_ID="$1"
SSM_JSON="$2"

# --- Sanity check ---
if [ ! -f "./documents/$SSM_JSON" ]; then
  echo "ERROR: JSON file '$SSM_JSON' not found!"
  exit 2
fi


# Strip directory + .json suffix
BASE_NAME=$(basename "$SSM_JSON" .json)

# Prefix with WBuilder-
DOC_NAME="WBuilder-$BASE_NAME"

if [ -z "$DOC_NAME" ]; then
  echo "ERROR: Could not derive document name from $SSM_JSON"
  exit 3
fi

echo "NOTE: Using Document Name = $DOC_NAME"
echo "NOTE: Targeting Instance ID = $MI_ID"

# --- Create (or update) the SSM document ---
echo "NOTE: Creating or updating SSM Document..."
aws ssm create-document \
  --name "$DOC_NAME" \
  --document-type "Command" \
  --content "file://$(pwd)/documents/$SSM_JSON" \
  --region us-east-1 2>/dev/null || \
aws ssm update-document \
  --name "$DOC_NAME" \
   --document-version '$LATEST' \
  --content "file://$(pwd)/documents/$SSM_JSON" \
  --region us-east-1

# --- Execute the SSM Document against the instance ---
echo "NOTE: Executing SSM Document..."
COMMAND_ID=$(aws ssm send-command \
  --targets "Key=instanceIds,Values=$MI_ID" \
  --document-name "$DOC_NAME" \
  --region us-east-1 \
  --query "Command.CommandId" \
  --output text)

if [ -z "$COMMAND_ID" ]; then
  echo "ERROR: Failed to send command."
  exit 4
fi

echo "NOTE: Command sent. CommandId = $COMMAND_ID"

# --- Poll for status ---
STATUS="InProgress"
while [[ "$STATUS" == "InProgress" || "$STATUS" == "Pending" ]]; do
  sleep 5
  STATUS=$(aws ssm list-command-invocations \
    --command-id "$COMMAND_ID" \
    --instance-id "$MI_ID" \
    --region us-east-1 \
    --query "CommandInvocations[0].Status" \
    --output text 2>/dev/null)
  echo "NOTE: Current Status = $STATUS"
done

# --- Final Status ---
if [ "$STATUS" == "Success" ]; then
  echo "NOTE: Command completed successfully"
else
  echo "WARNING: Command ended with status = $STATUS"
  echo "NOTE: Fetching detailed output..."
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$MI_ID" \
    --region us-east-1

    # --- Cleanup: Delete the SSM document ---  
    echo "NOTE: Deleting SSM Document $DOC_NAME ..."
    aws ssm delete-document \
        --name "$DOC_NAME" \
        --region us-east-1

    exit 5
fi

# --- Cleanup: Delete the SSM document ---
echo "NOTE: Deleting SSM Document $DOC_NAME ..."
aws ssm delete-document \
  --name "$DOC_NAME" \
  --region us-east-1
