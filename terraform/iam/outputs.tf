# =============================================================================
# Outputs
# =============================================================================

output "terraform_role_arn" {
  description = "ARN of the IAM role for Terraform operations (use this in Opsera)"
  value       = aws_iam_role.opsera_terraform_role.arn
}

output "terraform_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.opsera_terraform_role.name
}

output "terraform_policy_arn" {
  description = "ARN of the IAM policy"
  value       = aws_iam_policy.terraform_policy.arn
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile (if created)"
  value       = var.create_ec2_role ? aws_iam_instance_profile.terraform_profile[0].arn : null
}

# Instructions for next steps
output "next_steps" {
  description = "Instructions for using this role with Opsera"
  value = <<-EOT
    
    ========================================
    NEXT STEPS FOR OPSERA INTEGRATION
    ========================================
    
    1. Update the Opsera Kubernetes service account with this annotation:
       
       kubectl annotate serviceaccount <opsera-job-sa> \
         -n ${var.kubernetes_namespace} \
         eks.amazonaws.com/role-arn=${aws_iam_role.opsera_terraform_role.arn}
    
    2. Or, update the Opsera Tool Registry:
       - Go to Operations > Tool Registry > AWS
       - Create or edit your AWS tool
       - Set "IAM Role ARN" to: ${aws_iam_role.opsera_terraform_role.arn}
       - Enable "Use IAM Role" or "Cross Account IAM Role" option
    
    3. Test by running a pipeline that uses this AWS tool
    
    ========================================
  EOT
}

