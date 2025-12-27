# Opsera DevOps Agent - Terraform Outputs

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "api_endpoint" {
  description = "API endpoint URL (HTTP)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "api_endpoint_https" {
  description = "API endpoint URL (HTTPS) - only available if domain_name is configured"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : null
}

output "domain_name" {
  description = "Custom domain name (if configured)"
  value       = var.domain_name != "" ? var.domain_name : null
}

output "certificate_arn" {
  description = "ACM Certificate ARN (if created)"
  value       = var.domain_name != "" && var.create_certificate ? aws_acm_certificate.main[0].arn : null
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "Subnet IDs used"
  value       = slice(data.aws_subnets.default.ids, 0, 2)
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.main.name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}
