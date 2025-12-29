#!/bin/bash
# =============================================================================
# Simple EKS Deployment Script for Opsera Pipeline
# Uses S3 backend for persistent state
# =============================================================================
set -e

echo '============================================='
echo '  EKS Infrastructure Deployment'
echo '  Version: 1.0'
echo '============================================='
echo ''

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-west-2}"
S3_BUCKET="opsera-agentic-s3-v1"
S3_KEY="opsera-mcp-agents/eks-terraform.tfstate"
CLUSTER_NAME="opsera-mcp-dev"

# AWS Credentials (injected by Opsera or set manually)
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-AKIA3Q7I6RPKMB64IWZG}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-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}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
export AWS_REGION="${AWS_REGION}"

# -----------------------------------------------------------------------------
# Install Dependencies
# -----------------------------------------------------------------------------
echo '>>> Installing dependencies...'

# Install Terraform if not present
if ! command -v terraform &>/dev/null; then
    echo '>>> Installing Terraform 1.6.0...'
    apt-get update -qq
    apt-get install -y -qq wget unzip git curl jq
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
    unzip -o -q terraform_1.6.0_linux_amd64.zip
    mv -f terraform /usr/local/bin/
    rm -f terraform_1.6.0_linux_amd64.zip
    cd -
fi

# Install AWS CLI if not present  
if ! command -v aws &>/dev/null; then
    echo '>>> Installing AWS CLI...'
    apt-get update -qq
    apt-get install -y -qq awscli
fi

echo "Terraform: $(terraform version -json | jq -r '.terraform_version')"
echo "AWS CLI: $(aws --version)"
echo ''

# -----------------------------------------------------------------------------
# Check Current EKS Status
# -----------------------------------------------------------------------------
echo '>>> Checking existing EKS cluster...'
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Status:  ${CLUSTER_STATUS}"

if [ "${CLUSTER_STATUS}" == "CREATING" ]; then
    echo '>>> Waiting for cluster to become ACTIVE...'
    aws eks wait cluster-active --name "${CLUSTER_NAME}"
    echo '>>> Cluster is now ACTIVE!'
fi
echo ''

# -----------------------------------------------------------------------------
# Clone Repository
# -----------------------------------------------------------------------------
echo '>>> Cloning repository...'
git clone https://github.com/srinivas-opsera/opsera-mcp-agents.git repo
cd repo/terraform/aws
echo "Working directory: $(pwd)"
ls -la
echo ''

# -----------------------------------------------------------------------------
# Create S3 Bucket for State (if it doesn't exist)
# -----------------------------------------------------------------------------
echo '>>> Ensuring S3 bucket exists for state...'
if ! aws s3 ls "s3://${S3_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "  Bucket ${S3_BUCKET} exists"
else
    echo "  Creating bucket ${S3_BUCKET}..."
    aws s3 mb "s3://${S3_BUCKET}" --region us-east-1
    aws s3api put-bucket-versioning --bucket "${S3_BUCKET}" --versioning-configuration Status=Enabled
fi
echo ''

# -----------------------------------------------------------------------------
# Configure S3 Backend
# -----------------------------------------------------------------------------
echo '>>> Configuring S3 backend for state persistence...'
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
cat backend_override.tf
echo ''

# -----------------------------------------------------------------------------
# Initialize Terraform
# -----------------------------------------------------------------------------
echo '>>> Initializing Terraform...'
terraform init -input=false -reconfigure
echo ''

# -----------------------------------------------------------------------------
# Import Existing Resources (idempotent)
# -----------------------------------------------------------------------------
echo '>>> Importing existing resources into Terraform state...'

# Function to safely import a resource
import_if_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local import_id="$3"
    local check_cmd="$4"
    
    # Check if already in state
    if terraform state show "${resource_type}.${resource_name}" &>/dev/null; then
        echo "  [SKIP] ${resource_type}.${resource_name} already in state"
        return 0
    fi
    
    # Check if exists in AWS
    if eval "${check_cmd}" &>/dev/null; then
        echo "  [IMPORT] ${resource_type}.${resource_name} <- ${import_id}"
        terraform import -input=false "${resource_type}.${resource_name}" "${import_id}" || true
    else
        echo "  [NEW] ${resource_type}.${resource_name} will be created"
    fi
}

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  AWS Account: ${AWS_ACCOUNT_ID}"

# Import IAM Roles
import_if_exists "aws_iam_role" "eks_cluster" "${CLUSTER_NAME}-eks-cluster-role" \
    "aws iam get-role --role-name ${CLUSTER_NAME}-eks-cluster-role"

import_if_exists "aws_iam_role" "eks_nodes" "${CLUSTER_NAME}-eks-node-role" \
    "aws iam get-role --role-name ${CLUSTER_NAME}-eks-node-role"

import_if_exists "aws_iam_role" "argocd" "${CLUSTER_NAME}-argocd-role" \
    "aws iam get-role --role-name ${CLUSTER_NAME}-argocd-role"

import_if_exists "aws_iam_role" "app_workload" "${CLUSTER_NAME}-app-workload-role" \
    "aws iam get-role --role-name ${CLUSTER_NAME}-app-workload-role"

# Import ECR Repository
import_if_exists "aws_ecr_repository" "main" "opsera-mcp-agents" \
    "aws ecr describe-repositories --repository-names opsera-mcp-agents"

# Import VPC if exists
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
    import_if_exists "aws_vpc" "main" "${VPC_ID}" "echo exists"
fi

# Import EKS Cluster if exists
if [ "${CLUSTER_STATUS}" == "ACTIVE" ]; then
    import_if_exists "aws_eks_cluster" "main" "${CLUSTER_NAME}" "echo exists"
fi

echo ''

# -----------------------------------------------------------------------------
# Plan
# -----------------------------------------------------------------------------
echo '>>> Running Terraform plan...'
terraform plan -input=false -out=tfplan
echo ''

# -----------------------------------------------------------------------------
# Apply
# -----------------------------------------------------------------------------
echo '>>> Applying Terraform changes...'
terraform apply -auto-approve -input=false tfplan
echo ''

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
echo '============================================='
echo '  DEPLOYMENT COMPLETE!'
echo '============================================='
echo ''
echo '>>> Terraform Outputs:'
terraform output
echo ''
echo '>>> Configure kubectl with:'
terraform output -raw kubectl_config_command 2>/dev/null || echo "aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
echo ''

