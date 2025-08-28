# AWS Workspace Builder (WBuilder)

## Overview
AWS Workspace Builder is a **Packer-like automation tool** for **building custom AWS WorkSpaces images and bundles**.  
Instead of manually launching a WorkSpace, installing software, and capturing an image, this project provides an automated pipeline that:

1. Launches a WorkSpace from an AWS-provided base image.  
2. Uses AWS Systems Manager (SSM) to install additional software (e.g., Chrome, Notepad++).  
3. Validates the environment.  
4. Captures a **custom image**.  
5. Creates a **custom WorkSpace bundle** based on that image.  

The result is a reproducible, versioned image + bundle that can be reused across deployments.


## Key Features
- **Packer-like workflow** for WorkSpaces.  
- Starts with AWS-provided base images.  
- Installs software via **SSM automation documents**.  
- Produces validated **golden images** and **custom bundles**.  
- Fully automated with **Terraform + Bash scripts**.  

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

## AWS Diagram of WBuilder Environment

![AWS diagram](aws-workspace-builder.png)

## Build Workflow

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

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/)
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) 
* [Install Latest Terraform](https://developer.hashicorp.com/terraform/install)

If this is your first time watching our content, we recommend starting with this video: [AWS + Terraform: Easy Setup](https://youtu.be/BCMQo0CB9wk). It provides a step-by-step guide to properly configure Terraform, Packer, and the AWS CLI.  


## Download this Repository

```bash
git clone https://github.com/mamonaco1973/aws-workspace-builder.git
cd aws-workspace-builder
```


## Build the Code

Run [check_env](check_env.sh) to validate your environment, then run [apply](apply.sh) to provision the infrastructure.

```bash
develop-vm:~/aws-workspace-builder$ ./apply.sh
NOTE: Validating that required commands are found in your PATH.
NOTE: aws is found in the current PATH.
NOTE: terraform is found in the current PATH.
NOTE: All required commands are available.
NOTE: Checking AWS cli connection.
NOTE: Successfully logged into AWS.
Initializing the backend...
Initializing provider plugins...
- Reusing previous version of hashicorp/random from the dependency lock file
- Reusing previous version of hashicorp/aws from the dependency lock file
- Using previously-installed hashicorp/random v3.7.1
- Using previously-installed hashicorp/aws v5.89.0

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.
```


## Build Results


## Add an install to the Build