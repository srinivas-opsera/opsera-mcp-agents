#!/usr/bin/env bash
# =============================================================================
# Multi-Tenant EKS Deployment Script
# =============================================================================
# Deploys VPCs and EKS clusters for TenantA and TenantB (nonprod + prod)
# Usage: ./deploy-multi-tenant.sh [tenant] [environment]
#   Examples:
#     ./deploy-multi-tenant.sh                    # Deploy all tenants
#     ./deploy-multi-tenant.sh TenantA            # Deploy TenantA (both envs)
#     ./deploy-multi-tenant.sh TenantA nonprod    # Deploy TenantA nonprod only
# =============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$REPO_ROOT/terraform"
S3_BUCKET="opsera-agentic-s3-v1"
AWS_REGION="us-west-2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get tenant directory from key
get_tenant_dir() {
    local key="$1"
    case "$key" in
        "TenantA-nonprod") echo "tenant-a-nonprod" ;;
        "TenantA-prod") echo "tenant-a-prod" ;;
        "TenantB-nonprod") echo "tenant-b-nonprod" ;;
        "TenantB-prod") echo "tenant-b-prod" ;;
        *) echo "" ;;
    esac
}

# =============================================================================
# Prerequisites Check
# =============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform &>/dev/null; then
        log_error "Terraform not installed. Installing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install terraform
        else
            wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip -O /tmp/terraform.zip
            unzip -o -q /tmp/terraform.zip -d /tmp
            sudo mv /tmp/terraform /usr/local/bin/
        fi
    fi
    log_success "Terraform: $(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)"
    
    # Check AWS CLI
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI not installed"
        exit 1
    fi
    log_success "AWS CLI: $(aws --version | awk '{print $1}')"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    log_success "AWS Account: $(aws sts get-caller-identity --query 'Account' --output text)"
}

# =============================================================================
# Ensure S3 Bucket Exists
# =============================================================================
ensure_s3_bucket() {
    log_info "Checking S3 bucket for Terraform state..."
    
    if ! aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        log_warn "Bucket $S3_BUCKET does not exist. Creating..."
        aws s3 mb "s3://$S3_BUCKET" --region us-east-1
        aws s3api put-bucket-versioning \
            --bucket "$S3_BUCKET" \
            --versioning-configuration Status=Enabled
        log_success "Created bucket: $S3_BUCKET"
    else
        log_success "Bucket exists: $S3_BUCKET"
    fi
}

# =============================================================================
# Deploy Single Tenant Environment
# =============================================================================
deploy_tenant() {
    local tenant_key="$1"
    local tenant_dir
    tenant_dir=$(get_tenant_dir "$tenant_key")
    
    if [[ -z "$tenant_dir" ]]; then
        log_error "Unknown tenant: $tenant_key"
        return 1
    fi
    
    local dir_path="$TERRAFORM_DIR/tenants/$tenant_dir"
    
    if [[ ! -d "$dir_path" ]]; then
        log_error "Tenant directory not found: $dir_path"
        return 1
    fi
    
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Deploying: $tenant_key"
    log_info "═══════════════════════════════════════════════════════════════"
    
    cd "$dir_path"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -input=false -upgrade
    
    # Plan
    log_info "Planning changes..."
    terraform plan -input=false -out=tfplan
    
    # Apply
    log_info "Applying changes (this may take 15-20 minutes for EKS)..."
    terraform apply -input=false -auto-approve tfplan
    
    # Show outputs
    log_success "Deployment complete for $tenant_key"
    terraform output
    
    cd "$REPO_ROOT"
}

# =============================================================================
# Main
# =============================================================================
main() {
    local tenant_filter="${1:-}"
    local env_filter="${2:-}"
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║           Multi-Tenant EKS Deployment                             ║"
    echo "╠═══════════════════════════════════════════════════════════════════╣"
    echo "║  TenantA-nonprod: 10.1.0.0/16  │  TenantA-prod: 10.2.0.0/16      ║"
    echo "║  TenantB-nonprod: 10.3.0.0/16  │  TenantB-prod: 10.4.0.0/16      ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    ensure_s3_bucket
    
    # Determine which tenants to deploy
    local tenants_to_deploy=()
    
    if [[ -n "$tenant_filter" && -n "$env_filter" ]]; then
        # Specific tenant and environment
        tenants_to_deploy=("${tenant_filter}-${env_filter}")
    elif [[ -n "$tenant_filter" ]]; then
        # All environments for a specific tenant
        tenants_to_deploy=("${tenant_filter}-nonprod" "${tenant_filter}-prod")
    else
        # All tenants
        tenants_to_deploy=("TenantA-nonprod" "TenantA-prod" "TenantB-nonprod" "TenantB-prod")
    fi
    
    log_info "Will deploy: ${tenants_to_deploy[*]}"
    echo ""
    
    # Deploy each tenant
    for tenant in "${tenants_to_deploy[@]}"; do
        deploy_tenant "$tenant"
    done
    
    echo ""
    log_success "═══════════════════════════════════════════════════════════════"
    log_success "All deployments complete!"
    log_success "═══════════════════════════════════════════════════════════════"
    
    # Summary
    echo ""
    echo "📋 Summary of deployed clusters:"
    for tenant in "${tenants_to_deploy[@]}"; do
        local tenant_dir
        tenant_dir=$(get_tenant_dir "$tenant")
        if [[ -n "$tenant_dir" ]]; then
            local dir_path="$TERRAFORM_DIR/tenants/$tenant_dir"
            if [[ -d "$dir_path/.terraform" ]]; then
                local cluster_name
                cluster_name=$(cd "$dir_path" && terraform output -raw cluster_name 2>/dev/null || echo "N/A")
                echo "  • $tenant: $cluster_name"
            fi
        fi
    done
    
    echo ""
    echo "To configure kubectl for a cluster:"
    echo "  aws eks update-kubeconfig --name <cluster-name> --region $AWS_REGION"
}

main "$@"
