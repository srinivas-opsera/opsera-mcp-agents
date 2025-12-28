# ═══════════════════════════════════════════════════════════════════════════════
# Opsera MCP Agents - Terraform Backend Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Note: The backend configuration will be provided by Opsera pipeline
# during terraform init. This file serves as a template.
#
# Opsera will inject the following during pipeline execution:
# - bucket: S3 bucket for state storage
# - key: State file path
# - region: AWS region
# - encrypt: Enable encryption
# - dynamodb_table: For state locking (optional)
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    # Backend configuration injected by Opsera pipeline
    # Do not hardcode values here - they are managed by Opsera
  }
}

