# Opsera Pipeline Creation - API Best Practices

## Overview
Creating Opsera pipelines via API requires specific field formats and valid identifiers. This skill documents the correct approach.

## Pipeline Creation API

### Endpoint
```
POST /api/v2/pipeline/create
```

### Required Fields

#### Step `_id` Format
- Must be a valid **24-character MongoDB ObjectId**
- Example: `"6951fa00adaf282bd9ad0001"`
- Cannot be arbitrary strings or shorter IDs

```json
{
  "workflow": [
    {
      "_id": "6951fa00adaf282bd9ad0001",  // Valid 24-char ObjectId
      "name": "my-step",
      "active": true,
      "tool": { ... }
    }
  ]
}
```

### Complete Example - run_script Pipeline
```json
{
  "name": "my-pipeline-v1",
  "description": "Pipeline description",
  "active": true,
  "type": ["run_script"],
  "tags": [
    {"type": "category", "value": "deployment"}
  ],
  "workflow": [
    {
      "_id": "6951fa00adaf282bd9ad0001",
      "name": "deploy-step",
      "active": true,
      "tool": {
        "tool_identifier": "run_script",
        "configuration": {
          "type": "manual_entry",
          "script": "#!/bin/bash\necho 'Hello World'"
        }
      }
    }
  ]
}
```

## Native Terraform Tool Configuration

### Known Issues
1. `terraformVersion` field may not set the Docker image tag
2. Use `tag: "1.6.0"` instead of `terraformVersion: "1.6.0"`
3. Empty backend blocks in `backend.tf` cause silent failures

### Working Configuration
```json
{
  "tool_identifier": "terraform",
  "configuration": {
    "tag": "1.6.0",
    "stateFile": "manual",
    "terraformAction": "EXECUTE",
    "job": null,
    "threshold": {"type": "", "value": ""}
  }
}
```

### Backend Configuration
Never use empty backend blocks:
```hcl
# BAD - causes silent failures
terraform {
  backend "s3" {}
}

# GOOD - explicit configuration
terraform {
  backend "s3" {
    bucket  = "my-bucket"
    key     = "path/to/state.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| "Step is missing a valid _id" | Invalid ObjectId format | Use 24-char hex string |
| "Script was not included" | Wrong field name | Use `script` not `commands` |
| "Type not supported" | Wrong type value | Use `"manual_entry"` not `"github"` |
| "imageName: null" | terraformVersion not working | Use `tag` field instead |

## Searching for Pipelines
```
GET /api/v2/search?s=pipeline-name&t=pipeline&count=10
```

## Checking Pipeline Status
```
POST /api/v2/actions
{
  "action": "status",
  "type": "pipeline",
  "version": 1,
  "target": ["pipeline-id-1", "pipeline-id-2"]
}
```

