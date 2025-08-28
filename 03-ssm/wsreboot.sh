#!/bin/bash
set -euo pipefail
export AWS_DEFAULT_REGION="us-east-1"   # AWS region for all resources

# ----------------------------------------------------------------------
# Step 1. Find Workspace by tag
# ----------------------------------------------------------------------
WORKSPACE_ID=""

for wsid in $(aws workspaces describe-workspaces --query "Workspaces[].WorkspaceId" --output text); do
  if aws workspaces describe-tags --resource-id "$wsid" \
       --query "TagList[?Key=='Name' && Value=='WBuilder WorkSpace']" \
       --output text | grep -q "WBuilder WorkSpace"; then
    WORKSPACE_ID="$wsid"
    break
  fi
done

if [[ -z "$WORKSPACE_ID" ]]; then
  echo "ERROR: No WorkSpace found with tag Name=WBuilder WorkSpace" >&2
  exit 1
fi

echo "NOTE: Workspace for bundle build is $WORKSPACE_ID"

# ----------------------------------------------------------------------
# Step 2. Reboot the WorkSpace
# ----------------------------------------------------------------------
echo "NOTE: Rebooting WorkSpace $WORKSPACE_ID ..."
STATUS=$(aws workspaces reboot-workspaces \
  --reboot-workspace-requests "[{\"WorkspaceId\":\"$WORKSPACE_ID\"}]")

if [[ $? -ne 0 ]]; then
  echo $STATUS
  echo "ERROR: Failed to reboot WorkSpace $WORKSPACE_ID" >&2
  exit 1
fi

sleep 60  # There is a pretty big delay in the status update
echo "NOTE: Reboot command issued successfully."

# ----------------------------------------------------------------------
# Step 3. Ensure Workspace is AVAILABLE before creating an image
# ----------------------------------------------------------------------
echo "NOTE: Waiting for workspace $WORKSPACE_ID to become AVAILABLE..."
while true; do
  WS_STATUS=$(aws workspaces describe-workspaces \
    --workspace-ids "$WORKSPACE_ID" \
    --query "Workspaces[0].State" \
    --output text)

  echo "NOTE: Current state of workspace $WORKSPACE_ID is $WS_STATUS"

  case "$WS_STATUS" in
    AVAILABLE)
      echo "NOTE: Workspace $WORKSPACE_ID is AVAILABLE"
      break
      ;;
    ERROR|FAILED|TERMINATING|TERMINATED)
      echo "ERROR: Workspace $WORKSPACE_ID is in state $WS_STATUS, cannot proceed" >&2
      exit 1
      ;;
    *)
      sleep 60
      ;;
  esac
done
