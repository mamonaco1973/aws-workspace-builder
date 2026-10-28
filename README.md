# AWS Workspace Builder: Custom WorkSpaces Images and Bundles

A Packer-style pipeline for **Amazon WorkSpaces**. Instead of launching a
WorkSpace by hand, installing software and capturing it in the console,
`apply.sh` builds a throwaway domain and a build WorkSpace, installs
software on it through **AWS Systems Manager**, then captures a **custom
image** and creates a **custom bundle** from it. The image and bundle
outlive the build environment: tear the rest down and launch WorkSpaces
from the bundle in any directory.

The trick is getting SSM onto a WorkSpace, which isn't an EC2 instance.
The lab's **mini-AD** domain controller publishes a startup **GPO** on the
OU where new WorkSpaces land; the script registers the WorkSpace's SSM
agent with a **hybrid activation**, so it shows up as a managed instance
(`mi-…`) that Run Command can target.

| Piece | Where | Role |
|---|---|---|
| **mini-AD DC** | `ad-subnet` (private), `t3.small` | Ubuntu 24.04 running Samba as the DC for `wbuilder.workspaces.com` (`WBUILDER`); creates `Admin` (Domain Admins), the `Build_Workspaces` OU and the `SSM-Bootstrap-Script` GPO linked to it; reached over SSM |
| **AD Connector** | `vm-subnet-1` and `-2` (`use1-az6`, `use1-az4`) | Small; points at the DC's IP and signs in as `Admin` |
| **WorkSpaces directory** | us-east-1 | the connector registered with WorkSpaces; new WorkSpaces go in `Build_Workspaces`; internet access and maintenance mode on; users aren't local admins |
| **WBuilder WorkSpace** | WorkSpaces | the `Admin` user's WorkSpace from bundle `wsb-93xk71ss4` (the `workspace_bundle` variable); `STANDARD`, 80 GiB root, 50 GiB user, `ALWAYS_ON` |
| **HybridActivation** | Systems Manager | registration limit 1; role `ssm-hybrid-instance-role` with `AmazonSSMManagedInstanceCore` |
| **SSM documents** | `03-ssm/documents/` | `adtools.json` (AD and RSAT tools), `chrome.json` (Chrome Enterprise), `npp.json` (Notepad++ 8.8.5) |
| **Image and bundle** | WorkSpaces | `wbuilder-image-<timestamp>` and `wbuilder-bundle-<timestamp>` (`STANDARD`, 80 GiB root, 50 GiB user) |
| **Secrets Manager** | us-east-1 | `admin_ad_credentials` (`WBUILDER\Admin`) and `hybrid_activation` (activation ID and code) |
| **ad-vpc** | `10.0.0.0/24` | two public VM subnets, the private AD subnet, NAT gateway; DHCP options point DNS at the DC |

## Architecture

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="architecture-dark.svg">
  <img alt="apply.sh builds a Samba mini-AD domain controller for wbuilder.workspaces.com in a private subnet behind a NAT gateway, an AD Connector that points at it, and a WorkSpaces directory whose new WorkSpaces land in the Build_Workspaces OU. The Admin user's WBuilder WorkSpace joins the domain through the connector; a startup GPO linked to that OU registers its SSM agent with a hybrid activation, so it appears in Systems Manager as a managed instance. The scripts then send Run Command documents that install the AD tools, Chrome and Notepad++, reboot the WorkSpace, capture a custom image from it and create a custom bundle from the image. Secrets Manager holds the Admin password, which Terraform gives the AD Connector, and the hybrid activation ID and code." src="architecture-light.svg">
</picture>

Regenerate with `python3 make_diagram.py`.

- **`01-directory/`**: the VPC, subnets and NAT gateway, the Admin
  password, the hybrid activation and its secret, the DC's IAM role and
  security group, and the DC itself (`scripts/mini-ad.sh.template` and
  `scripts/users.json.template`).
- **`02-workspace/`**: the AD Connector, the WorkSpaces role and directory
  registration, and the WBuilder WorkSpace.
- **`03-ssm/`**: the SSM documents, `ssm-execute.sh` (run one document
  against one managed instance), `ssm-build.sh` (run them all) and
  `wsreboot.sh`.
- **`ssm-wait.sh`**, **`build_bundle.sh`**: wait for the WorkSpace to come
  online in SSM; capture the image and create the bundle.

## How the build works

1. **Directory.** The DC provisions the Samba domain with RFC2307
   attributes, creates `Admin` and the seed users and groups, creates the
   `Build_Workspaces` OU, writes the `SSM-Bootstrap-Script` GPO to SYSVOL
   with the activation ID and code, links it to the OU, and reboots.
   Terraform waits 180 seconds before pointing the VPC's DNS at it.
2. **WorkSpace.** The AD Connector and WorkSpaces registration are created
   and the Admin WorkSpace is provisioned into `Build_Workspaces`.
3. **SSM registration.** At startup the GPO script waits five minutes,
   registers the SSM agent with the hybrid activation and leaves a marker
   file so it only does this once. `ssm-wait.sh` polls Systems Manager
   (every 30 seconds, up to an hour) until a managed instance with that
   activation ID is online.
4. **Software.** `ssm-build.sh` runs `adtools.json`, reboots the WorkSpace
   and waits for it to be `AVAILABLE`, then runs `chrome.json` and
   `npp.json`. For each document, `ssm-execute.sh` creates it as
   `WBuilder-<name>`, sends it, polls until it finishes, writes
   `<name>.log` with stdout and stderr, and deletes the document. A failed
   document stops the build.
5. **Image and bundle.** `build_bundle.sh` reboots the WorkSpace again,
   creates `wbuilder-image-<timestamp>`, waits for it to be `AVAILABLE`, and
   creates `wbuilder-bundle-<timestamp>` from it.

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/)
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [Install Terraform](https://developer.hashicorp.com/terraform/install)
* [Install jq](https://jqlang.github.io/jq/download/)
* [Install a WorkSpaces client](https://clients.amazonworkspaces.com/), or use the web client

If this is your first time watching our content, we recommend starting with
this video: [AWS + Terraform: Easy Setup](https://youtu.be/BCMQo0CB9wk).

## Deploy

```bash
git clone https://github.com/mamonaco1973/aws-workspace-builder.git
cd aws-workspace-builder
./apply.sh
```

`apply.sh` runs `check_env.sh`, applies `01-directory` and `02-workspace`,
then runs `ssm-wait.sh`, `03-ssm/ssm-build.sh` and `build_bundle.sh`. It
ends by running `validate.sh`, which prints the directory's registration
code:

```
NOTE: Bundle created. BundleId=wsb-xxxxxxxxx
NOTE: Workspaces Registration Code is 'WSpdx+XXXXXX'
```

## Try it

Add your own software with a new SSM document. For example, 7-Zip:

1. Save this as `03-ssm/documents/7zip.json`:

   ```json
   {
     "schemaVersion": "2.2",
     "description": "Download and silently install 7-Zip",
     "mainSteps": [
       {
         "action": "aws:runPowerShellScript",
         "name": "Install7Zip",
         "inputs": {
           "runCommand": [
             "$ErrorActionPreference = 'Stop'",
             "$ProgressPreference = 'SilentlyContinue'",
             "$Installer = \"$env:TEMP\\7z_installer.exe\"",
             "Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7z2301-x64.exe' -OutFile $Installer -UseBasicParsing",
             "Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -NoNewWindow",
             "Write-Output '7-Zip installation complete.'"
           ]
         }
       }
     ]
   }
   ```

2. Find the managed instance ID (the `mi-…` that `ssm-wait.sh` printed, or
   **Systems Manager > Fleet Manager**) and run it:

   ```bash
   cd 03-ssm
   ./ssm-execute.sh mi-0123456789abcdef0 7zip.json
   ```

3. Check `7zip.log`, or the command's output in **Systems Manager > Run
   Command**.
4. Sign in to the WorkSpace as `Admin` (password in `admin_ad_credentials`,
   registration code from `validate.sh`) and confirm 7-Zip is installed.
5. Run `./build_bundle.sh` again for a new image and bundle with 7-Zip in
   it. To bake it into every build, add it to `ssm-build.sh`.

## Teardown

```bash
./destroy.sh
```

`destroy.sh` deregisters the managed instance, destroys `02-workspace`,
deletes both secrets without a recovery window, and destroys
`01-directory`. It **doesn't delete the images or bundles**: they're the
build's output. Share them with other accounts, copy them to other regions,
or launch WorkSpaces from them in a directory joined to your own AD, and
delete them in the WorkSpaces console when you no longer need them.

## Notes

- **Lab only.** The DC's security group allows every AD port from
  `0.0.0.0/0` (it has no public IP), and its role has
  `SecretsManagerReadWrite` and `AmazonSSMFullAccess`.
- The activation code is written in plain text into the GPO's startup
  script in SYSVOL, which any domain user can read. The activation allows
  one registration.
- `Administrator`, `Admin` and the seed user `sysadmin-us` all share the
  one random password, which is also passed to the DC in its user data.
- The base bundle ID is hard-coded as the `workspace_bundle` default; if
  AWS retires it, pass a current Windows bundle from
  `aws workspaces describe-workspace-bundles --owner AMAZON`.
- The WorkSpace is `ALWAYS_ON`, which bills monthly, and every run of
  `build_bundle.sh` leaves another image and bundle behind.
