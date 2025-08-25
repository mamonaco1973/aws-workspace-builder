# AWS Workspace Builder

## Overview
AWS Workspace Builder is a **Packer-like automation tool** for **building custom AWS WorkSpaces images and bundles**.  
Instead of manually launching a WorkSpace, installing software, and capturing an image, this project provides an automated pipeline that:

1. Launches a WorkSpace from an AWS-provided base image.  
2. Uses AWS Systems Manager (SSM) to install additional software (e.g., Chrome, Notepad++).  
3. Validates the environment.  
4. Captures a **custom image**.  
5. Creates a **custom WorkSpace bundle** based on that image.  

The result is a reproducible, versioned image + bundle that can be reused across deployments.

---

## Key Features
- **Packer-like workflow** for WorkSpaces.  
- Starts with AWS-provided base images.  
- Installs software via **SSM automation documents**.  
- Produces validated **golden images** and **custom bundles**.  
- Fully automated with **Terraform + Bash scripts**.  

---

## Project Structure
```text
aws-workspace-builder-main/
├── apply.sh              # End-to-end deploy + build wrapper
├── destroy.sh            # Cleanup environment
├── check_env.sh          # Pre-flight validation
├── validate.sh           # Post-install validation checks
├── build_bundle.sh       # Capture image + create WorkSpace bundle
├── ssm-wait.sh           # Wait for SSM agent readiness
│
├── 01-directory/         # Mini-AD + networking + IAM (Terraform)
├── 02-workspace/         # WorkSpace + AD Connector (Terraform)
├── 03-ssm/               # SSM automation (Chrome, Notepad++ installs)
```

---

## Workflow

![diagram](workflow.png)

1. **Environment pre-check**  
   ```bash
   ./check_env.sh
   ```

2. **Deploy Mini-AD + networking**  
   ```bash
   cd 01-directory
   terraform init && terraform apply
   ```

3. **Deploy WorkSpace + AD Connector**  
   ```bash
   cd ../02-workspace
   terraform init && terraform apply
   ```

4. **Wait for SSM agent**  
   ```bash
   ./ssm-wait.sh
   ```

5. **Install software via SSM**  
   ```bash
   cd 03-ssm
   ./ssm-execute.sh
   ```

6. **Validate installation**  
   ```bash
   ./validate.sh
   ```

7. **Capture custom image + bundle**  
   ```bash
   ./build_bundle.sh
   ```

8. **Tear down environment (optional)**  
   ```bash
   ./destroy.sh
   ```

---

## Requirements
- AWS CLI configured with proper IAM permissions.  
- Terraform installed and in `PATH`.  
- Bash shell environment (Linux/macOS/WSL).  
- Permissions for EC2, WorkSpaces, SSM, and Directory Service.  

---

## Notes
- Default installs: **Google Chrome**, **Notepad++**.  
- Additional software can be added by dropping new SSM documents into `03-ssm/documents/`.  
- The captured image and bundle are reusable across accounts/regions (with proper sharing).  
