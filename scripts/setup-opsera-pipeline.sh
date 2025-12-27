#!/bin/bash
# Opsera Pipeline Setup Script
# Configures and registers the pipeline with Opsera platform

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
PIPELINE_FILE="$PROJECT_ROOT/opsera-pipeline.json"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Opsera Pipeline Setup                                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Check if Opsera CLI is installed
check_opsera_cli() {
    echo -e "\n${YELLOW}Checking Opsera CLI...${NC}"
    
    if command -v opsera &> /dev/null; then
        echo -e "${GREEN}✓ Opsera CLI found${NC}"
        return 0
    else
        echo -e "${YELLOW}Opsera CLI not found. You can:${NC}"
        echo -e "  1. Install Opsera CLI: npm install -g @opsera/cli"
        echo -e "  2. Or import the pipeline manually via Opsera UI"
        return 1
    fi
}

# Validate pipeline configuration
validate_pipeline() {
    echo -e "\n${YELLOW}Validating pipeline configuration...${NC}"
    
    if [ ! -f "$PIPELINE_FILE" ]; then
        echo -e "${RED}Error: Pipeline file not found at $PIPELINE_FILE${NC}"
        exit 1
    fi
    
    # Check if it's valid JSON
    if ! python3 -m json.tool "$PIPELINE_FILE" > /dev/null 2>&1; then
        if ! node -e "JSON.parse(require('fs').readFileSync('$PIPELINE_FILE'))" 2>/dev/null; then
            echo -e "${RED}Error: Invalid JSON in pipeline file${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Pipeline configuration is valid${NC}"
}

# Configure Git webhook for auto-trigger
setup_git_webhook() {
    echo -e "\n${YELLOW}Setting up Git webhook for auto-trigger...${NC}"
    
    # Get the current git remote
    REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
    
    if [ -z "$REPO_URL" ]; then
        echo -e "${YELLOW}Warning: No git remote found. Webhook setup skipped.${NC}"
        return
    fi
    
    echo -e "${GREEN}✓ Repository: $REPO_URL${NC}"
    echo -e "${YELLOW}To enable auto-trigger:${NC}"
    echo -e "  1. Go to your repository settings"
    echo -e "  2. Add a webhook pointing to your Opsera instance"
    echo -e "  3. Configure events: push, pull_request"
    echo -e "  4. Set content type: application/json"
}

# Register pipeline with Opsera
register_pipeline() {
    echo -e "\n${YELLOW}Registering pipeline with Opsera...${NC}"
    
    if command -v opsera &> /dev/null; then
        # Using Opsera CLI
        echo -e "${YELLOW}Using Opsera CLI to register pipeline...${NC}"
        opsera pipeline create --file "$PIPELINE_FILE" || {
            echo -e "${YELLOW}CLI registration failed. Please import manually.${NC}"
        }
    else
        echo -e "${YELLOW}Manual registration required:${NC}"
        echo -e "  1. Login to Opsera platform"
        echo -e "  2. Navigate to Pipelines → Create New"
        echo -e "  3. Import from JSON: $PIPELINE_FILE"
        echo -e "  4. Configure secrets in pipeline settings"
    fi
}

# Print setup instructions
print_instructions() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Opsera Pipeline Setup Instructions                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${GREEN}Pipeline Configuration:${NC} $PIPELINE_FILE"
    
    echo -e "\n${YELLOW}Required Secrets (configure in Opsera):${NC}"
    echo -e "  • AWS_ACCESS_KEY_ID     - AWS access key for ECR/ECS"
    echo -e "  • AWS_SECRET_ACCESS_KEY - AWS secret key"
    echo -e "  • VALID_API_KEY         - MCP server API key"
    echo -e "  • SLACK_WEBHOOK_URL     - (Optional) Slack notifications"
    
    echo -e "\n${YELLOW}Pipeline Features:${NC}"
    echo -e "  ✓ Auto-trigger on push to main/develop branches"
    echo -e "  ✓ Code change detection (src/**, Dockerfile, package.json)"
    echo -e "  ✓ Infrastructure change detection (infrastructure/**)"
    echo -e "  ✓ Security scanning (secrets, dependencies, SAST, IaC)"
    echo -e "  ✓ Docker build with ECR push"
    echo -e "  ✓ Terraform apply for infra changes"
    echo -e "  ✓ Multi-environment deployment (dev → staging → prod)"
    echo -e "  ✓ Health checks and smoke tests"
    echo -e "  ✓ DORA metrics tracking"
    
    echo -e "\n${YELLOW}Deployment Environments:${NC}"
    echo -e "  • Development: Auto-deploy on main/develop"
    echo -e "  • Staging:     Auto-deploy after dev (main branch)"
    echo -e "  • Production:  Manual approval required (main + v* tags)"
    
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo -e "  1. Import opsera-pipeline.json to Opsera platform"
    echo -e "  2. Configure the required secrets"
    echo -e "  3. Set up Git webhook for auto-trigger"
    echo -e "  4. Push code changes to trigger the pipeline"
}

# Main
main() {
    validate_pipeline
    check_opsera_cli || true
    setup_git_webhook
    register_pipeline
    print_instructions
}

main "$@"

