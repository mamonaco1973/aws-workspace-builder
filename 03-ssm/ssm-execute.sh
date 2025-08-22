#!/bin/bash
# =====================================================================
# Script: ssm-execute
# Purpose:
#   - Automate the execution of a custom AWS Systems Manager (SSM) 
#     document against a specified managed instance.
#   - Handles document creation/update, execution, polling, and cleanup.
#
# Usage:
#   ./ssm-execute <MI_ID> <SSM_JSON_FILE>
#
# Parameters:
#   MI_ID         - The Managed Instance ID (e.g., mi-0123456789abcdef)
#   SSM_JSON_FILE - The name of the JSON file (in ./documents/) that 
#                   defines the SSM document content.
#
# Exit Codes:
#   1 - Incorrect usage (missing parameters).
#   2 - JSON file not found.
#   3 - Unable to derive a valid document name.
#   4 - Failed to send SSM command.
#   5 - Command execution failed (non-success status).
#
# Notes:
#   - Script assumes AWS CLI is installed and configured.
#   - Script executes in the `us-east-1` region (hardcoded).
#   - Temporary SSM document is always cleaned up at the end.
# =====================================================================


# --- Input Validation ------------------------------------------------
# Ensure exactly two arguments are provided (MI_ID + JSON file).
if [ $# -ne 2 ]; then
  echo "Usage: $0 <MI_ID> <SSM_JSON_FILE>"
  exit 1
fi

MI_ID="$1"
SSM_JSON="$2"


# --- Sanity Check ----------------------------------------------------
# Verify that the provided JSON file exists under ./documents/.
if [ ! -f "./documents/$SSM_JSON" ]; then
  echo "ERROR: JSON file '$SSM_JSON' not found!"
  exit 2
fi


# --- Derive Document Name --------------------------------------------
# Remove directory path and .json suffix.
BASE_NAME=$(basename "$SSM_JSON" .json)

# Prefix document name with "WBuilder-" for namespace isolation.
DOC_NAME="WBuilder-$BASE_NAME"

# Fail if document name could not be derived (defensive check).
if [ -z "$DOC_NAME" ]; then
  echo "ERROR: Could not derive document name from $SSM_JSON"
  exit 3
fi

echo "NOTE: Using Document Name = $DOC_NAME"
echo "NOTE: Targeting Instance ID = $MI_ID"


# --- Create or Update SSM Document -----------------------------------
# Attempt to create the SSM document. If it already exists, update it.
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


# --- Execute SSM Document --------------------------------------------
# Send the document to the target instance and capture the Command ID.
echo "NOTE: Executing SSM Document..."
COMMAND_ID=$(aws ssm send-command \
  --targets "Key=instanceIds,Values=$MI_ID" \
  --document-name "$DOC_NAME" \
  --region us-east-1 \
  --query "Command.CommandId" \
  --output text)

# Abort if the command could not be sent.
if [ -z "$COMMAND_ID" ]; then
  echo "ERROR: Failed to send command."
  exit 4
fi

echo "NOTE: Command sent. CommandId = $COMMAND_ID"


# --- Poll for Command Status -----------------------------------------
STATUS="InProgress"

# Continuously check until the command finishes (Success/Failed/etc.).
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

echo "NOTE: Creating log file ${BASE_NAME}.log"

{
  echo "---- $(date) ----"
  echo "[STDOUT]"
  aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$MI_ID" \
      --region us-east-1 \
      --query "StandardOutputContent" \
      --output text
  echo "[STDERR]"
  aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$MI_ID" \
      --region us-east-1 \
      --query "StandardErrorContent" \
      --output text
} > ${BASE_NAME}.log

# --- Evaluate Final Status -------------------------------------------
if [ "$STATUS" == "Success" ]; then
  echo "NOTE: Command completed successfully"
else
  echo "WARNING: Command ended with status = $STATUS"

  # Cleanup document even on failure.
  echo "NOTE: Deleting SSM Document $DOC_NAME ..."
  aws ssm delete-document \
    --name "$DOC_NAME" \
    --region us-east-1

  exit 5
fi

# --- Cleanup ----------------------------------------------------------
# Always remove the temporary document after execution completes.
echo "NOTE: Deleting SSM Document $DOC_NAME ..."
aws ssm delete-document \
  --name "$DOC_NAME" \
  --region us-east-1
