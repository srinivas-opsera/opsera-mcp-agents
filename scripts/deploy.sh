#!/bin/bash
# Opsera DevOps Agent - AWS Deployment Script
# Builds Docker image for linux/amd64 and deploys to AWS ECS Fargate

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure/terraform"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Opsera DevOps Agent - AWS Deployment                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Check required tools
check_requirements() {
    echo -e "\n${YELLOW}Checking requirements...${NC}"
    
    for cmd in docker aws terraform; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✓ All requirements met${NC}"
}

# Get Terraform outputs
get_terraform_outputs() {
    echo -e "\n${YELLOW}Getting Terraform outputs...${NC}"
    
    cd "$TERRAFORM_DIR"
    
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
    ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
    ECS_SERVICE=$(terraform output -raw ecs_service_name 2>/dev/null || echo "")
    ACCOUNT_ID=$(terraform output -raw account_id 2>/dev/null || echo "")
    
    if [ -z "$ECR_REPOSITORY_URL" ]; then
        echo -e "${RED}Error: Could not get ECR repository URL. Run 'terraform apply' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ AWS Region: $AWS_REGION${NC}"
    echo -e "${GREEN}✓ ECR Repository: $ECR_REPOSITORY_URL${NC}"
    echo -e "${GREEN}✓ ECS Cluster: $ECS_CLUSTER${NC}"
    echo -e "${GREEN}✓ ECS Service: $ECS_SERVICE${NC}"
}

# Build Docker image for linux/amd64 (required for ECS Fargate)
build_image() {
    echo -e "\n${YELLOW}Building Docker image for linux/amd64...${NC}"
    
    cd "$PROJECT_ROOT"
    
    # Build for amd64 architecture (ECS Fargate requirement)
    docker build --platform linux/amd64 -t opsera-devops-agent:latest .
    
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
}

# Login to ECR
ecr_login() {
    echo -e "\n${YELLOW}Logging into ECR...${NC}"
    
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    echo -e "${GREEN}✓ Logged into ECR${NC}"
}

# Push to ECR
push_to_ecr() {
    echo -e "\n${YELLOW}Pushing image to ECR...${NC}"
    
    docker tag opsera-devops-agent:latest "$ECR_REPOSITORY_URL:latest"
    
    # Tag with git SHA for versioning
    GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    docker tag opsera-devops-agent:latest "$ECR_REPOSITORY_URL:$GIT_SHA"
    
    docker push "$ECR_REPOSITORY_URL:latest"
    docker push "$ECR_REPOSITORY_URL:$GIT_SHA"
    
    echo -e "${GREEN}✓ Image pushed to ECR${NC}"
    echo -e "${GREEN}  - $ECR_REPOSITORY_URL:latest${NC}"
    echo -e "${GREEN}  - $ECR_REPOSITORY_URL:$GIT_SHA${NC}"
}

# Update ECS service
update_ecs_service() {
    echo -e "\n${YELLOW}Updating ECS service...${NC}"
    
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_SERVICE" \
        --force-new-deployment \
        --region "$AWS_REGION" \
        > /dev/null
    
    echo -e "${GREEN}✓ ECS service updated${NC}"
    echo -e "${YELLOW}Waiting for deployment to stabilize...${NC}"
    
    aws ecs wait services-stable \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVICE" \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}✓ Deployment complete!${NC}"
}

# Print deployment info
print_info() {
    cd "$TERRAFORM_DIR"
    API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "")
    
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Deployment Complete!                                         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${GREEN}API Endpoint:${NC} $API_ENDPOINT"
    echo -e "\n${YELLOW}Test the deployment:${NC}"
    echo -e "  curl $API_ENDPOINT/health"
    echo -e "\n${YELLOW}MCP SSE Endpoint:${NC}"
    echo -e "  $API_ENDPOINT/sse"
}

# Main
main() {
    check_requirements
    get_terraform_outputs
    build_image
    ecr_login
    push_to_ecr
    update_ecs_service
    print_info
}

main "$@"
