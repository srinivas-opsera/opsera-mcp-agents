# Skill: Opsera run_script Pipeline Configuration

## Overview
The `run_script` tool in Opsera is a bare shell executor. It does NOT automatically inject credentials, clone repositories, or provide pre-installed tools.

## Key Learnings

### 1. Script Configuration Requirements

```json
{
  "tool": {
    "tool_identifier": "run_script",
    "configuration": {
      "type": "manual_entry",    // MUST be "manual_entry", NOT "github"
      "script": "#!/bin/bash\necho 'hello'"  // Field is "script", NOT "commands"
    }
  }
}
```

**Common Mistakes:**
- ❌ Using `type: "github"` → Error: "Type [github] selected is not supported"
- ❌ Using `commands` field → Error: "A Script was not included"
- ✅ Use `type: "manual_entry"` and `script` field

### 2. AWS Credentials Are NOT Injected

The `run_script` tool does NOT inject AWS credentials even with `awsToolConfigId`:

```json
{
  "configuration": {
    "awsToolConfigId": "67621e88ba7ecea7a6cda161"  // This is IGNORED!
  }
}
```

**Workarounds:**
1. Hardcode credentials in script (NOT recommended for production)
2. Run scripts locally with AWS credentials configured
3. Use a different Opsera tool that supports credential injection

### 3. No Auto Git Clone

The `run_script` executor does NOT auto-clone repositories. You must:

```bash
#!/bin/bash
# Clone manually in your script
git clone https://github.com/your-org/your-repo.git repo
cd repo
```

### 4. No Pre-installed Tools

The container is bare. Install tools in your script:

```bash
#!/bin/bash
# Install Terraform
wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip -o -q terraform_1.6.0_linux_amd64.zip -d /tmp
mv /tmp/terraform /usr/local/bin/

# Install AWS CLI
curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -o -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update

# Install kubectl
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/
```

### 5. Pipeline Step ID Requirements

Step `_id` must be a valid 24-character MongoDB ObjectId:

```json
{
  "_id": "6951fa00adaf282bd9ad0001",  // Valid ObjectId
  "name": "my-step",
  "active": true
}
```

### 6. Environment Image is Ignored

The `environmentConfiguration.image` field is ignored:

```json
{
  "environmentConfiguration": {
    "image": "hashicorp/terraform:1.6.0"  // IGNORED!
  }
}
```

## Best Practices

1. **Always install dependencies** at the start of your script
2. **Use non-interactive flags**: `apt-get install -y -qq`, `unzip -o -q`
3. **Clone repos explicitly** if you need source code
4. **Handle credentials via environment variables** set outside the script
5. **Extract binaries to /tmp** to avoid conflicts with repo directories

## Example: Complete Working Script

```bash
#!/bin/bash
set -e

echo "=== Installing Dependencies ==="
apt-get update -qq
apt-get install -y -qq git curl unzip jq

# Install Terraform
cd /tmp
wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip -o -q terraform_1.6.0_linux_amd64.zip
mv terraform /usr/local/bin/
cd -

# Install AWS CLI
curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -o -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
rm -rf /tmp/awscliv2.zip /tmp/aws

# Verify
terraform version
aws --version

echo "=== Cloning Repository ==="
git clone https://github.com/your-org/your-repo.git repo
cd repo

echo "=== Running Terraform ==="
cd terraform/aws
terraform init -input=false
terraform plan -input=false
terraform apply -auto-approve -input=false

echo "=== Done ==="
```

