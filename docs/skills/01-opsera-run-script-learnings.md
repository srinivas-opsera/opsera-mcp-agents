# Opsera run_script Tool - Critical Learnings

## Overview
The `run_script` tool in Opsera is a **bare shell executor** that runs scripts in an isolated container. It does NOT have the conveniences of other Opsera tools.

## Key Limitations

### 1. No Automatic Credential Injection
```yaml
# ❌ DOES NOT WORK - awsToolConfigId is ignored
configuration:
  awsToolConfigId: "67621e88ba7ecea7a6cda161"
```

**What happens:** The script runs but `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are NOT set.

**Workarounds:**
- Hardcode credentials in script (NOT recommended for production)
- Use IAM roles if running on AWS infrastructure
- Pass credentials via Opsera environment variables (if supported)

### 2. No Automatic Git Clone
Unlike Jenkins or other CI tools, `run_script` does NOT automatically clone your repository.

```bash
# ✅ You must manually clone in your script
git clone https://github.com/your-org/your-repo.git repo
cd repo
```

### 3. Template Syntax Does NOT Work
```yaml
# ❌ DOES NOT WORK
script: |
  export AWS_ACCESS_KEY_ID="${{aws.accessKeyId}}"
  export AWS_SECRET_ACCESS_KEY="${{aws.secretAccessKey}}"

# ❌ DOES NOT WORK
script: |
  export AWS_ACCESS_KEY_ID="${{ TOOL.speri-aws.ACCESS_KEY_ID }}"
```

### 4. Environment Image is Ignored
```yaml
# ❌ environmentConfiguration.image is IGNORED
environmentConfiguration:
  image: "hashicorp/terraform:1.6.0"
```

**Solution:** Install tools manually in your script:
```bash
# Install Terraform
wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip -o -q terraform_1.6.0_linux_amd64.zip -d /tmp
mv /tmp/terraform /usr/local/bin/
```

## Correct Configuration Syntax

### Pipeline Step Configuration
```json
{
  "_id": "6951fa00adaf282bd9ad0001",  // Must be 24-char MongoDB ObjectId
  "name": "my-script-step",
  "active": true,
  "tool": {
    "tool_identifier": "run_script",
    "configuration": {
      "type": "manual_entry",           // ✅ Must be "manual_entry", NOT "github"
      "script": "#!/bin/bash\necho 'Hello World'"  // ✅ Use "script", NOT "commands"
    }
  }
}
```

### Common Mistakes

| Mistake | Correct |
|---------|---------|
| `"type": "github"` | `"type": "manual_entry"` |
| `"commands": "..."` | `"script": "..."` |
| Missing `_id` | Include valid 24-char ObjectId |
| `awsToolConfigId` for creds | Install AWS CLI + set env vars manually |

## Working Script Template

```bash
#!/bin/bash
set -e

echo '=== My Pipeline Script ==='

# Check for required credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERROR: AWS credentials not set!"
    exit 1
fi

# Install dependencies
apt-get update -qq
apt-get install -y -qq git curl wget unzip jq

# Install AWS CLI
if ! command -v aws &>/dev/null; then
    curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -o -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
fi

# Install Terraform
if ! command -v terraform &>/dev/null; then
    wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip -O /tmp/terraform.zip
    unzip -o -q /tmp/terraform.zip -d /tmp
    mv /tmp/terraform /usr/local/bin/
fi

# Install kubectl
if ! command -v kubectl &>/dev/null; then
    curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
    chmod +x kubectl && mv kubectl /usr/local/bin/
fi

# Clone repository (run_script doesn't do this automatically!)
git clone https://github.com/your-org/your-repo.git repo
cd repo

# Your actual work here
echo "Working directory: $(pwd)"
ls -la

echo '=== Done ==='
```

## Interactive Prompts

The container runs non-interactively. Use flags to prevent prompts:

```bash
# ❌ Will hang waiting for user input
unzip terraform.zip

# ✅ Use -o to overwrite without prompting
unzip -o terraform.zip

# ✅ Use -y for apt-get
apt-get install -y package-name

# ✅ Use --yes or similar for other tools
npx --yes create-react-app my-app
```

## File Path Conflicts

Be careful when extracting binaries in a repo directory:

```bash
# ❌ If repo has a "terraform/" directory, this fails
unzip terraform.zip  # Creates ./terraform binary
mv terraform /usr/local/bin/  # Error: terraform is a directory

# ✅ Extract to /tmp first
unzip -o terraform.zip -d /tmp
mv /tmp/terraform /usr/local/bin/
```

## Debugging Tips

1. **Print environment variables:**
```bash
env | sort
```

2. **Check working directory:**
```bash
pwd
ls -la
```

3. **Verify tool installations:**
```bash
which terraform || echo "terraform not found"
terraform version || echo "terraform failed"
```

4. **Check AWS credentials:**
```bash
echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-NOT SET}"
echo "AWS_SECRET_ACCESS_KEY length: ${#AWS_SECRET_ACCESS_KEY}"
```

