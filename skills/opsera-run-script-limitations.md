# Opsera `run_script` Tool - Limitations and Workarounds

## Overview
The Opsera `run_script` tool is a "bare" shell executor that does NOT automatically inject credentials or clone repositories. Understanding these limitations is critical for successful pipeline execution.

## Key Limitations Discovered

### 1. AWS Credentials Are NOT Auto-Injected
- Setting `awsToolConfigId` in the configuration does **NOT** inject AWS credentials
- Template syntaxes like `{{aws.accessKeyId}}`, `${{ TOOL.speri-aws.ACCESS_KEY_ID }}` do **NOT** work
- The only working methods are:
  - Hardcoding credentials (NOT recommended for production)
  - Running scripts locally with pre-configured AWS CLI
  - Using a different Opsera tool that supports credential injection

### 2. No Automatic Git Clone
- `run_script` does NOT automatically clone your repository
- You must manually clone in the script:
  ```bash
  git clone https://github.com/your-org/your-repo.git repo
  cd repo
  ```
- For private repos, you need to embed credentials or use SSH keys

### 3. Custom Docker Image Is Ignored
- Setting `environmentConfiguration.image` does NOT use your custom image
- The executor runs in a base Ubuntu image without your tools
- You must manually install all tools (Terraform, kubectl, AWS CLI, etc.)

### 4. Correct Configuration Syntax
```json
{
  "tool_identifier": "run_script",
  "configuration": {
    "type": "manual_entry",    // NOT "github"
    "script": "#!/bin/bash\n...",  // NOT "commands"
    "awsToolConfigId": "..."   // Does NOT inject creds, but may be required
  }
}
```

## Workarounds

### Install Tools Manually in Script
```bash
#!/bin/bash
set -e

# Install Terraform
if ! command -v terraform &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq wget unzip
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
    unzip -o -q terraform_1.6.0_linux_amd64.zip
    mv terraform /usr/local/bin/
    cd -
fi

# Install AWS CLI
if ! command -v aws &>/dev/null; then
    apt-get install -y -qq awscli
fi

# Install kubectl
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/
```

### Non-Interactive Flags Required
```bash
# Use -o to overwrite without prompting
unzip -o -q file.zip

# Use -y for apt-get
apt-get install -y -qq package

# Use --yes for npm/npx
npx --yes some-package
```

### Avoid Directory Conflicts
```bash
# Extract to /tmp to avoid conflicts with repo directories
unzip -o -q terraform.zip -d /tmp
mv /tmp/terraform /usr/local/bin/
```

## When to Use run_script
- Simple scripts that don't need AWS credentials
- Public repository cloning
- Post-processing steps after other tools
- Debug/diagnostic scripts

## When to Use Alternative Tools
- **Native Terraform tool**: For Terraform with proper state management
- **AWS Deploy tools**: For deployments needing AWS credentials
- **Local execution**: For scripts needing AWS credentials

