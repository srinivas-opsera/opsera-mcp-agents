# Skill: Opsera Pipeline Patterns

## Overview
Patterns and best practices for creating and debugging Opsera pipelines, learned through extensive trial and error.

---

## Key Learnings

### 1. `run_script` Tool Behavior

**Critical: `run_script` is a "raw" executor** - it does NOT:
- Auto-inject AWS credentials from Tool Registry
- Perform git clone automatically
- Pre-install any tools (Terraform, kubectl, AWS CLI)

**What DOES work:**
```json
{
  "tool_identifier": "run_script",
  "configuration": {
    "type": "manual_entry",           // MUST be "manual_entry", not "github"
    "script": "#!/bin/bash\n..."      // MUST be "script", not "commands"
  }
}
```

**What DOES NOT work:**
```json
{
  "awsToolConfigId": "...",           // Ignored - credentials not injected
  "type": "github",                   // Causes "type not supported" error
  "commands": "..."                   // Wrong field name
}
```

### 2. Pipeline Step `_id` Format

Pipeline steps require a valid 24-character MongoDB ObjectId:
```json
{
  "_id": "6951fa00adaf282bd9ad0001",   // Valid format
  "name": "step-name",
  "active": true,
  "tool": { ... }
}
```

**Invalid formats that cause errors:**
- `"69520001000000000000001"` (wrong length)
- `"step-1"` (not ObjectId format)
- Omitting `_id` entirely

### 3. Native Terraform Tool Configuration

The native Terraform tool requires specific fields:
```json
{
  "tool_identifier": "terraform",
  "configuration": {
    "tag": "1.6.0",                    // Docker image tag, not "terraformVersion"
    "stateFile": "manual",
    "job": null,
    "threshold": {"type": "", "value": ""}
  }
}
```

**Common pitfalls:**
- `terraformVersion` field is ignored
- Empty S3 backend block in `backend.tf` causes silent failure
- `imageName: "hashicorp/terraform:null"` means tag wasn't set

---

## Patterns

### Pattern 1: Self-Contained Script Pipeline

Since `run_script` doesn't inject credentials or clone repos, make scripts self-contained:

```bash
#!/bin/bash
set -e

# 1. Validate credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "ERROR: AWS_ACCESS_KEY_ID not set"
    exit 1
fi

# 2. Install dependencies
apt-get update -qq
apt-get install -y -qq git curl unzip

# 3. Clone repository manually
git clone https://github.com/org/repo.git repo
cd repo

# 4. Install tools
curl -LO https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip -o -q terraform_1.6.0_linux_amd64.zip -d /tmp
mv /tmp/terraform /usr/local/bin/

# 5. Run actual work
terraform init
terraform apply -auto-approve
```

### Pattern 2: Avoid Directory Conflicts

When extracting tools, avoid conflicts with repo directories:
```bash
# BAD - conflicts with terraform/ directory in repo
unzip terraform.zip
mv terraform /usr/local/bin/

# GOOD - extract to /tmp first
unzip -o -q terraform.zip -d /tmp
mv /tmp/terraform /usr/local/bin/
```

### Pattern 3: Non-Interactive Operations

Always use non-interactive flags:
```bash
apt-get install -y -qq ...    # -y for yes, -qq for quiet
unzip -o -q ...               # -o for overwrite, -q for quiet
terraform apply -auto-approve -input=false
```

---

## Debugging Checklist

When an Opsera pipeline fails:

1. **Check step configuration:**
   - Is `type` set to `"manual_entry"`?
   - Is field named `script` (not `commands`)?
   - Is `_id` a valid 24-char ObjectId?

2. **Check environment:**
   - Are AWS credentials available? (`echo $AWS_ACCESS_KEY_ID`)
   - Is the repo cloned? (`ls -la`)
   - Are tools installed? (`which terraform`)

3. **Check for silent failures:**
   - Empty Terraform backend blocks
   - Missing tool versions (`imageName: "...:null"`)
   - Network timeouts during package downloads

---

## Reference: Working Pipeline Creation

```python
# Opsera API call structure
{
  "name": "my-pipeline-v1",
  "description": "Description",
  "active": true,
  "type": ["run_script"],
  "workflow": [{
    "_id": "6951fa00adaf282bd9ad0001",
    "name": "step-name",
    "active": true,
    "tool": {
      "tool_identifier": "run_script",
      "configuration": {
        "type": "manual_entry",
        "script": "#!/bin/bash\nset -e\necho 'Hello World'"
      }
    }
  }]
}
```

