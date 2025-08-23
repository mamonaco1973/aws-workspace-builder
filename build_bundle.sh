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
# Step 1b. Ensure Workspace is AVAILABLE before creating an image
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

# ----------------------------------------------------------------------
# Step 2. Create image from Workspace
# ----------------------------------------------------------------------
IMAGE_NAME="wbuilder-image-$(date +%Y%m%d%H%M%S)"
IMAGE_DESCRIPTION="Image created from workspace $WORKSPACE_ID"

echo "NOTE: Creating image '$IMAGE_NAME' from workspace ${WORKSPACE_ID}..."
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
echo "NOTE: Waiting for image $IMAGE_ID to become AVAILABLE..."
while true; do
  STATUS=$(aws workspaces describe-workspace-images \
    --image-ids "$IMAGE_ID" \
    --query "Images[0].State" \
    --output text)

  echo "NOTE: Status of image $IMAGE_ID is $STATUS"

  case "$STATUS" in
    AVAILABLE)
      echo "NOTE: Image $IMAGE_ID is now AVAILABLE"
      break
      ;;
    ERROR|FAILED)
      echo "ERROR: Image creation failed for $IMAGE_ID" >&2
      exit 1
      ;;
    *)
      sleep 120
      ;;
  esac
done

# ----------------------------------------------------------------------
# Step 4. Create bundle from the image
# ----------------------------------------------------------------------

BUNDLE_NAME="wbuilder-bundle-$(date +%Y%m%d%H%M%S)"
BUNDLE_DESCRIPTION="Bundle created from image $IMAGE_ID"

echo "NOTE: Creating bundle $BUNDLE_NAME from image $IMAGE_ID ..."

BUNDLE_ID=$(aws workspaces create-workspace-bundle \
  --bundle-name "$BUNDLE_NAME" \
  --bundle-description "$BUNDLE_DESCRIPTION" \
  --image-id "$IMAGE_ID" \
  --compute-type-name STANDARD \
  --user-storage Capacity=50 \
  --root-storage Capacity=80 \
  --query "BundleId" \
  --output text)

if [[ -z "$BUNDLE_ID" || "$BUNDLE_ID" == "None" ]]; then
  echo "ERROR: Failed to create bundle from image $IMAGE_ID" >&2
  exit 1
fi

echo "NOTE: Bundle created. BundleId=$BUNDLE_ID"
