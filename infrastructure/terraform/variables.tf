# Opsera DevOps Agent - Terraform Variables

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "opsera-devops-agent"
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 3847
}

variable "task_cpu" {
  description = "CPU units for the task (1 vCPU = 1024)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory for the task in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "min_count" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 10
}

variable "api_key" {
  description = "API key for authentication"
  type        = string
  sensitive   = true
  default     = "opsera-production-key-change-me"
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (optional)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID to use (default VPC)"
  type        = string
  default     = "vpc-008d194c7dbbb8eae"
}

