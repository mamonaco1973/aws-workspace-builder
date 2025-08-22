#!/bin/bash

# -------------------------------------------------
# Step 1: Retrieve WorkSpaces Registration Code
# -------------------------------------------------
regcode=$(aws workspaces describe-workspace-directories \
  --region us-east-1 \
  --query "Directories[?DirectoryName=='wbuilder.workspaces.com'].RegistrationCode" \
  --output text)  # 🔐 This code is needed to register WorkSpaces clients

# --------------------------------------------
# Step 2: Output Registration Code and URL
# --------------------------------------------
echo "NOTE: Workspaces Registration Code is '$regcode'"

