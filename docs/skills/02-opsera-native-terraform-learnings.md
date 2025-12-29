# Opsera Native Terraform Tool - Critical Learnings

## Overview
The native Terraform tool in Opsera is a specialized executor for Terraform operations. However, it has several quirks that can cause silent failures.

## Key Issues Discovered

### 1. Terraform Version Configuration

The `terraformVersion` field does NOT properly set the Docker image tag:

```yaml
# ❌ Results in "hashicorp/terraform:null"
configuration:
  terraformVersion: "1.6.0"

# ❌ Also doesn't work
buildTool:
  terraformVersion: "1.6.0"
```

**Solution:** Use the `tag` field (discovered from working pipelines):

```yaml
# ✅ This works
configuration:
  tag: "1.6.0"
```

### 2. Empty Backend Configuration

An empty S3 backend block causes `terraform init` to fail silently:

```hcl
# ❌ Causes silent failure
terraform {
  backend "s3" {
    # Backend configuration injected by Opsera pipeline
    # Do not hardcode values here
  }
}
```

The error message is: `"Error state returned but no valid error message returned."`

**Solution:** Either:

1. Hardcode the backend configuration:
```hcl
# ✅ Explicit backend config
terraform {
  backend "s3" {
    bucket  = "my-terraform-state-bucket"
    key     = "project/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

2. Or use local backend for testing:
```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

3. Or generate backend config dynamically in script:
```bash
cat > backend_override.tf << EOF
terraform {
  backend "s3" {
    bucket  = "${S3_BUCKET}"
    key     = "${S3_KEY}"
    region  = "us-east-1"
    encrypt = true
  }
}
EOF
```

### 3. Required Fields from Working Pipelines

Analysis of working pipeline `686e8a80adaf282bd9ad194a` revealed these fields:

```json
{
  "tool": {
    "tool_identifier": "terraform",
    "configuration": {
      "tag": "1.6.0",           // ✅ Use this, not terraformVersion
      "stateFile": "manual",    // Required
      "job": null,
      "threshold": {
        "type": "",
        "value": ""
      }
    }
  }
}
```

## Error Messages and Solutions

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `"imageName": "hashicorp/terraform:null"` | Missing/wrong version config | Use `tag: "1.6.0"` |
| `"Error state returned but no valid error message returned."` | Empty backend block or init failure | Hardcode backend config |
| `"Error fetching step configuration"` | Invalid step configuration | Check all required fields |

## Debugging the Native Terraform Tool

1. **Check the API response logs** for `imageName` field:
```json
{
  "imageName": "hashicorp/terraform:1.6.0"  // ✅ Should show version
}
```

2. **Look for terraform init errors** in pipeline logs

3. **Verify S3 bucket access** before running pipeline

## Alternative: Use run_script Instead

Given the complexity of the native Terraform tool, using `run_script` with manual Terraform installation is often more reliable:

```bash
#!/bin/bash
set -e

# Install Terraform
wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip -O /tmp/tf.zip
unzip -o -q /tmp/tf.zip -d /tmp
mv /tmp/terraform /usr/local/bin/

# Clone repo and run
git clone https://github.com/org/repo.git
cd repo/terraform

# Create backend config
cat > backend_override.tf << EOF
terraform {
  backend "s3" {
    bucket = "my-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
EOF

terraform init -input=false -reconfigure
terraform plan -input=false -out=tfplan
terraform apply -auto-approve -input=false tfplan
```

This approach gives you:
- Full control over Terraform version
- Explicit backend configuration
- Better error visibility
- Easier debugging

