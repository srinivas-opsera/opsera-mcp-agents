# ═══════════════════════════════════════════════════════════════════════════════
# Opsera MCP Agents - AWS Provider Configuration
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "opsera-mcp-agents"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "opsera"
    }
  }
}

