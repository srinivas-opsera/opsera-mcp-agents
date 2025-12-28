# ═══════════════════════════════════════════════════════════════════════════════
# Opsera MCP Agents - Terraform Variables
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# General Configuration
# ─────────────────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "opsera-mcp-agents"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Networking Configuration
# ─────────────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# ─────────────────────────────────────────────────────────────────────────────────
# ECS Configuration
# ─────────────────────────────────────────────────────────────────────────────────

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "opsera-mcp-cluster"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 3847
}

variable "container_cpu" {
  description = "CPU units for the container (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory for the container in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# ECR Configuration
# ─────────────────────────────────────────────────────────────────────────────────

variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "opsera-mcp-agents"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────────

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

