# ═══════════════════════════════════════════════════════════════════════════════
# Opsera MCP Agents - Terraform Backend Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Backend configuration will be injected by Opsera via -backend-config flags
# during terraform init command.
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    bucket  = "Opsera-agentic-s3-v1"
    key     = "opsera-mcp-agents/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
