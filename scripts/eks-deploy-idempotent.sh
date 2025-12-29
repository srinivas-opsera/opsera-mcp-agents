#!/bin/bash
# =============================================================================
# Idempotent EKS Deployment Script
# - Checks if resources exist before importing
# - Safe to run multiple times
# - Only creates/updates what's needed
# =============================================================================
set -e

echo '============================================='
echo '  Idempotent EKS Deployment'
echo '  Safe to run multiple times'
echo '============================================='

# AWS credentials (replace with your own or use Opsera tool injection when available)
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-AKIA3Q7I6RPKMB64IWZG}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-53Ah2EPYxzpDYKStKmziIcLlWFukWCY09zZCKwIN}"
export AWS_DEFAULT_REGION="${AWS_REGION:-us-west-2}"
export AWS_REGION="${AWS_REGION:-us-west-2}"

# Configuration
CLUSTER_NAME="opsera-mcp-dev"
REPO_URL="https://github.com/srinivas-opsera/opsera-mcp-agents.git"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Check if a resource is already in Terraform state
in_state() {
  terraform state list 2>/dev/null | grep -q "^$1$"
}

# Import a resource if not already in state
import_if_missing() {
  local resource_addr="$1"
  local resource_id="$2"
  local resource_name="$3"
  
  if in_state "$resource_addr"; then
    echo "  ✓ $resource_name already in state"
  else
    echo "  → Importing $resource_name..."
    if terraform import "$resource_addr" "$resource_id" 2>/dev/null; then
      echo "  ✓ $resource_name imported"
    else
      echo "  ⚠ $resource_name import failed (may not exist yet)"
    fi
  fi
}

# Check if AWS resource exists
aws_resource_exists() {
  local type="$1"
  local id="$2"
  
  case "$type" in
    vpc)
      aws ec2 describe-vpcs --vpc-ids "$id" &>/dev/null
      ;;
    subnet)
      aws ec2 describe-subnets --subnet-ids "$id" &>/dev/null
      ;;
    igw)
      aws ec2 describe-internet-gateways --internet-gateway-ids "$id" &>/dev/null
      ;;
    nat)
      aws ec2 describe-nat-gateways --nat-gateway-ids "$id" --filter "Name=state,Values=available,pending" &>/dev/null
      ;;
    eip)
      aws ec2 describe-addresses --allocation-ids "$id" &>/dev/null
      ;;
    sg)
      aws ec2 describe-security-groups --group-ids "$id" &>/dev/null
      ;;
    rtb)
      aws ec2 describe-route-tables --route-table-ids "$id" &>/dev/null
      ;;
    eks)
      aws eks describe-cluster --name "$id" &>/dev/null
      ;;
    iam_role)
      aws iam get-role --role-name "$id" &>/dev/null
      ;;
    ecr)
      aws ecr describe-repositories --repository-names "$id" &>/dev/null
      ;;
    oidc)
      aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$id" &>/dev/null
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Install Dependencies
# -----------------------------------------------------------------------------

echo ''
echo '>>> Installing dependencies...'
if ! command -v terraform &>/dev/null; then
  apt-get update -qq
  apt-get install -y -qq wget unzip git curl jq awscli
  
  echo '>>> Installing Terraform...'
  wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
  unzip -o -q terraform_1.6.0_linux_amd64.zip
  mv -f terraform /usr/local/bin/
  rm -f terraform_1.6.0_linux_amd64.zip
fi

terraform version
aws --version

# -----------------------------------------------------------------------------
# Check EKS Cluster Status
# -----------------------------------------------------------------------------

echo ''
echo '>>> Checking EKS cluster status...'
if aws_resource_exists eks "$CLUSTER_NAME"; then
  CLUSTER_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text)
  CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.status' --output text)
  echo "  Cluster: $CLUSTER_NAME"
  echo "  Version: $CLUSTER_VERSION"
  echo "  Status:  $CLUSTER_STATUS"
  
  if [ "$CLUSTER_STATUS" = "UPDATING" ]; then
    echo ''
    echo '>>> Cluster is updating, waiting for completion...'
    aws eks wait cluster-active --name "$CLUSTER_NAME"
    echo '  ✓ Cluster is now active'
  fi
else
  echo "  Cluster $CLUSTER_NAME does not exist yet (will be created)"
fi

# -----------------------------------------------------------------------------
# Clone Repository
# -----------------------------------------------------------------------------

echo ''
echo '>>> Setting up Terraform workspace...'
if [ -d "repo" ]; then
  cd repo
  git pull
else
  git clone "$REPO_URL" repo
  cd repo
fi
cd terraform/aws

# -----------------------------------------------------------------------------
# Initialize Terraform
# -----------------------------------------------------------------------------

echo ''
echo '>>> Initializing Terraform...'
terraform init -input=false

# -----------------------------------------------------------------------------
# Discover Existing Resources
# -----------------------------------------------------------------------------

echo ''
echo '>>> Discovering existing AWS resources...'

# Get resource IDs from AWS
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=opsera-mcp-dev-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
echo "  VPC: $VPC_ID"

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  # Get subnets
  PUBLIC_SUBNET_0=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*2a*" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "None")
  PUBLIC_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*2b*" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "None")
  PRIVATE_SUBNET_0=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*2a*" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "None")
  PRIVATE_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*2b*" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "None")
  
  # Get gateways
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "None")
  NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "None")
  
  if [ "$NAT_ID" != "None" ] && [ -n "$NAT_ID" ]; then
    EIP_ALLOC=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_ID" --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text 2>/dev/null || echo "None")
  else
    EIP_ALLOC="None"
  fi
  
  # Get route tables
  PUBLIC_RTB=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "None")
  PRIVATE_RTB=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "None")
  
  # Get security group
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*eks-cluster-sg*" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
  
  echo "  Public Subnets: $PUBLIC_SUBNET_0, $PUBLIC_SUBNET_1"
  echo "  Private Subnets: $PRIVATE_SUBNET_0, $PRIVATE_SUBNET_1"
  echo "  Internet Gateway: $IGW_ID"
  echo "  NAT Gateway: $NAT_ID"
  echo "  EIP Allocation: $EIP_ALLOC"
  echo "  Route Tables: $PUBLIC_RTB, $PRIVATE_RTB"
  echo "  Security Group: $SG_ID"
fi

# Get EKS OIDC
if aws_resource_exists eks "$CLUSTER_NAME"; then
  OIDC_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || echo "")
  OIDC_ID=$(echo "$OIDC_URL" | sed 's|.*/||')
  ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
  OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}"
  echo "  OIDC ARN: $OIDC_ARN"
fi

# -----------------------------------------------------------------------------
# Import Existing Resources
# -----------------------------------------------------------------------------

echo ''
echo '>>> Importing existing resources into Terraform state...'

# ECR
if aws_resource_exists ecr "opsera-mcp-agents"; then
  import_if_missing "aws_ecr_repository.main" "opsera-mcp-agents" "ECR Repository"
fi

# IAM Roles
if aws_resource_exists iam_role "opsera-mcp-dev-eks-cluster-role"; then
  import_if_missing "aws_iam_role.eks_cluster" "opsera-mcp-dev-eks-cluster-role" "EKS Cluster Role"
  import_if_missing "aws_iam_role_policy_attachment.eks_cluster_policy" "opsera-mcp-dev-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" "EKS Cluster Policy Attachment"
  import_if_missing "aws_iam_role_policy_attachment.eks_vpc_resource_controller" "opsera-mcp-dev-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSVPCResourceController" "VPC Resource Controller Policy"
fi

if aws_resource_exists iam_role "opsera-mcp-dev-eks-node-role"; then
  import_if_missing "aws_iam_role.eks_nodes" "opsera-mcp-dev-eks-node-role" "EKS Node Role"
  import_if_missing "aws_iam_role_policy_attachment.eks_worker_node_policy" "opsera-mcp-dev-eks-node-role/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" "Worker Node Policy"
  import_if_missing "aws_iam_role_policy_attachment.eks_cni_policy" "opsera-mcp-dev-eks-node-role/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" "CNI Policy"
  import_if_missing "aws_iam_role_policy_attachment.eks_container_registry" "opsera-mcp-dev-eks-node-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" "Container Registry Policy"
fi

if aws_resource_exists iam_role "opsera-mcp-dev-argocd-role"; then
  import_if_missing "aws_iam_role.argocd" "opsera-mcp-dev-argocd-role" "ArgoCD Role"
  import_if_missing "aws_iam_role_policy.argocd_ecr" "opsera-mcp-dev-argocd-role:opsera-mcp-dev-argocd-ecr-policy" "ArgoCD ECR Policy"
fi

if aws_resource_exists iam_role "opsera-mcp-dev-app-workload-role"; then
  import_if_missing "aws_iam_role.app_workload" "opsera-mcp-dev-app-workload-role" "App Workload Role"
fi

# VPC Resources
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  import_if_missing "aws_vpc.main" "$VPC_ID" "VPC"
  
  [ "$PUBLIC_SUBNET_0" != "None" ] && import_if_missing "aws_subnet.public[0]" "$PUBLIC_SUBNET_0" "Public Subnet 0"
  [ "$PUBLIC_SUBNET_1" != "None" ] && import_if_missing "aws_subnet.public[1]" "$PUBLIC_SUBNET_1" "Public Subnet 1"
  [ "$PRIVATE_SUBNET_0" != "None" ] && import_if_missing "aws_subnet.private[0]" "$PRIVATE_SUBNET_0" "Private Subnet 0"
  [ "$PRIVATE_SUBNET_1" != "None" ] && import_if_missing "aws_subnet.private[1]" "$PRIVATE_SUBNET_1" "Private Subnet 1"
  
  [ "$IGW_ID" != "None" ] && import_if_missing "aws_internet_gateway.main" "$IGW_ID" "Internet Gateway"
  [ "$EIP_ALLOC" != "None" ] && import_if_missing "aws_eip.nat[0]" "$EIP_ALLOC" "Elastic IP"
  [ "$NAT_ID" != "None" ] && import_if_missing "aws_nat_gateway.main[0]" "$NAT_ID" "NAT Gateway"
  
  [ "$PUBLIC_RTB" != "None" ] && import_if_missing "aws_route_table.public" "$PUBLIC_RTB" "Public Route Table"
  [ "$PRIVATE_RTB" != "None" ] && import_if_missing "aws_route_table.private" "$PRIVATE_RTB" "Private Route Table"
  
  [ "$PUBLIC_SUBNET_0" != "None" ] && [ "$PUBLIC_RTB" != "None" ] && import_if_missing "aws_route_table_association.public[0]" "${PUBLIC_SUBNET_0}/${PUBLIC_RTB}" "Public RTA 0"
  [ "$PUBLIC_SUBNET_1" != "None" ] && [ "$PUBLIC_RTB" != "None" ] && import_if_missing "aws_route_table_association.public[1]" "${PUBLIC_SUBNET_1}/${PUBLIC_RTB}" "Public RTA 1"
  [ "$PRIVATE_SUBNET_0" != "None" ] && [ "$PRIVATE_RTB" != "None" ] && import_if_missing "aws_route_table_association.private[0]" "${PRIVATE_SUBNET_0}/${PRIVATE_RTB}" "Private RTA 0"
  [ "$PRIVATE_SUBNET_1" != "None" ] && [ "$PRIVATE_RTB" != "None" ] && import_if_missing "aws_route_table_association.private[1]" "${PRIVATE_SUBNET_1}/${PRIVATE_RTB}" "Private RTA 1"
  
  [ "$SG_ID" != "None" ] && import_if_missing "aws_security_group.eks_cluster" "$SG_ID" "Security Group"
fi

# EKS Cluster
if aws_resource_exists eks "$CLUSTER_NAME"; then
  import_if_missing "aws_eks_cluster.main" "$CLUSTER_NAME" "EKS Cluster"
  
  # OIDC Provider
  if [ -n "$OIDC_ARN" ] && aws_resource_exists oidc "$OIDC_ARN"; then
    import_if_missing "aws_iam_openid_connect_provider.eks" "$OIDC_ARN" "OIDC Provider"
  fi
fi

# -----------------------------------------------------------------------------
# Show Current State
# -----------------------------------------------------------------------------

echo ''
echo '>>> Current Terraform state:'
terraform state list 2>/dev/null | head -30 || echo "  (empty)"

# -----------------------------------------------------------------------------
# Apply Changes
# -----------------------------------------------------------------------------

echo ''
echo '>>> Running terraform apply...'
terraform apply -auto-approve -input=false

# -----------------------------------------------------------------------------
# Output Results
# -----------------------------------------------------------------------------

echo ''
echo '>>> Deployment Outputs:'
terraform output

echo ''
echo '============================================='
echo '  ✅ DEPLOYMENT COMPLETE!'
echo '============================================='
echo ''
echo 'Next Steps:'
echo '1. Configure kubectl:'
echo "   aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
echo ''
echo '2. Verify cluster:'
echo '   kubectl get nodes'
echo ''
echo '3. Install ArgoCD:'
echo '   kubectl apply -k gitops/argocd/'
echo ''

