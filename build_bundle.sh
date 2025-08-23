#!/bin/bash
set -euo pipefail

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
# Step 2. Create image from Workspace
# ----------------------------------------------------------------------
IMAGE_NAME="wbuilder-image-$(date +%Y%m%d%H%M%S)"
IMAGE_DESCRIPTION="Image created from workspace $WORKSPACE_ID"

echo "NOTE: Creating image '$IMAGE_NAME' from workspace $WORKSPACE_ID ..."
IMAGE_ID=$(aws workspaces create-workspace-image \
  --workspace-id "$WORKSPACE_ID" \
  --name "$IMAGE_NAME" \
  --description "$IMAGE_DESCRIPTION" \
  --query "ImageId" \
  --output text)

if [[ -z "$IMAGE_ID" || "$IMAGE_ID" == "None" ]]; then
  echo "ERROR: Failed to create workspace image" >&2
  exit 1
fi

echo "NOTE: Image creation started. ImageId=$IMAGE_ID"

# ----------------------------------------------------------------------
# Step 3. Poll until image is ready
# ----------------------------------------------------------------------
echo "NOTE: Waiting for image $IMAGE_ID to become AVAILABLE ..."
while true; do
  STATUS=$(aws workspaces describe-workspace-images \
    --image-ids "$IMAGE_ID" \
    --query "Images[0].State" \
    --output text)

  echo "STATUS: $STATUS"

  case "$STATUS" in
    AVAILABLE)
      echo "SUCCESS: Image $IMAGE_ID is now AVAILABLE"
      break
      ;;
    ERROR|FAILED)
      echo "ERROR: Image creation failed for $IMAGE_ID" >&2
      exit 1
      ;;
    *)
      sleep 30
      ;;
  esac
done

