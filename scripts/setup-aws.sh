#!/bin/bash
# Opsera DevOps Agent - AWS Setup Script
# Configures AWS CLI and initializes Terraform infrastructure

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure/terraform"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Opsera DevOps Agent - AWS Setup                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

check_aws_cli() {
    echo -e "\n${YELLOW}Checking AWS CLI...${NC}"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed.${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: brew install awscli"
        else
            echo "Install from: https://aws.amazon.com/cli/"
        fi
        exit 1
    fi
    
    aws --version
    echo -e "${GREEN}✓ AWS CLI installed${NC}"
}

check_terraform() {
    echo -e "\n${YELLOW}Checking Terraform...${NC}"
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Terraform is not installed.${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: brew install terraform"
        else
            echo "Install from: https://terraform.io/downloads"
        fi
        exit 1
    fi
    
    terraform --version
    echo -e "${GREEN}✓ Terraform installed${NC}"
}

verify_aws_credentials() {
    echo -e "\n${YELLOW}Verifying AWS credentials...${NC}"
    
    if aws sts get-caller-identity &> /dev/null; then
        IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
        echo -e "${GREEN}✓ AWS credentials configured: $IDENTITY${NC}"
    else
        echo -e "${RED}AWS credentials not configured or invalid.${NC}"
        echo "Run: aws configure"
        exit 1
    fi
}

init_terraform() {
    echo -e "\n${YELLOW}Initializing Terraform...${NC}"
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfvars" ]; then
        if [ -f "terraform.tfvars.example" ]; then
            echo -e "${YELLOW}Creating terraform.tfvars from example...${NC}"
            cp terraform.tfvars.example terraform.tfvars
            echo -e "${YELLOW}⚠ Please edit terraform.tfvars with your configuration${NC}"
        fi
    fi
    
    terraform init
    echo -e "${GREEN}✓ Terraform initialized${NC}"
}

plan_terraform() {
    echo -e "\n${YELLOW}Planning Terraform deployment...${NC}"
    
    cd "$TERRAFORM_DIR"
    terraform plan -out=tfplan
    echo -e "${GREEN}✓ Terraform plan created${NC}"
}

apply_terraform() {
    echo -e "\n${YELLOW}Ready to deploy infrastructure.${NC}"
    
    cd "$TERRAFORM_DIR"
    
    read -p "Apply Terraform plan? (y/N): " APPLY
    if [[ "$APPLY" =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        echo -e "${GREEN}✓ Infrastructure deployed!${NC}"
        echo -e "\n${BLUE}Outputs:${NC}"
        terraform output
    else
        echo -e "${YELLOW}Skipped. Run 'cd infrastructure/terraform && terraform apply' when ready.${NC}"
    fi
}

print_next_steps() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Setup Complete!                                              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "  1. Edit infrastructure/terraform/terraform.tfvars"
    echo -e "  2. Run: ./scripts/deploy.sh"
}

main() {
    check_aws_cli
    check_terraform
    verify_aws_credentials
    init_terraform
    plan_terraform
    apply_terraform
    print_next_steps
}

main "$@"
