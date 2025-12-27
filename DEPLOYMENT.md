# Opsera DevOps Agent - Deployment Guide

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Cursor IDE                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  MCP Client (SSE Transport)                                       │  │
│  │  Configured in: ~/.cursor/mcp.json                                │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ SSE Connection (Authenticated)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS Infrastructure                             │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Application Load Balancer                                        │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│                                    ▼                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  ECS Fargate Service                                              │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Opsera DevOps Agent MCP Server                             │  │  │
│  │  │  - SSE Transport for MCP Protocol                           │  │  │
│  │  │  - Protected prompts & tools                                │  │  │
│  │  │  - API Key authentication                                   │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed
- Terraform installed
- Node.js 20+

## Initial Infrastructure Setup

1. **Configure Terraform variables:**

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

2. **Deploy infrastructure:**

```bash
terraform init
terraform apply
```

3. **Note the outputs:**
   - `api_endpoint` - URL for the MCP server
   - `ecr_repository_url` - ECR repository for Docker images

## Deploying Updates

Use the deploy script:

```bash
./scripts/deploy.sh
```

This will:
1. Build Docker image for linux/amd64
2. Push to ECR
3. Update ECS service
4. Wait for deployment to stabilize

## Cursor MCP Configuration

Add to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "opsera-devops-agent": {
      "type": "sse",
      "url": "http://<ALB_DNS>/sse",
      "headers": {
        "Authorization": "Bearer <YOUR_API_KEY>"
      }
    }
  }
}
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (no auth) |
| `/sse` | GET | SSE connection for MCP protocol |
| `/message` | POST | Message endpoint for MCP protocol |
| `/tools` | POST | List available tools (legacy) |
| `/prompts` | POST | List available prompts (legacy) |

## Available Tools

- `opsera_create_pipeline` - Create production-ready CI/CD pipelines
- `opsera_security_scan` - Run security scans with compliance mapping
- `opsera_dora_metrics` - Generate DORA metrics reports

## Available Prompts

- `create-pipeline` - CI/CD pipeline generation expert
- `security-audit` - Security audit with compliance frameworks
- `k8s-deploy` - Kubernetes deployment best practices
- `dora-report` - DORA metrics analysis

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | 3847 |
| `VALID_API_KEY` | API key for authentication | - |
| `NODE_ENV` | Environment | production |

## Local Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Build for production
npm run build

# Run production build
npm start
```

## Troubleshooting

### ECS Tasks Not Starting

1. Check CloudWatch logs: `/ecs/opsera-devops-agent`
2. Verify ECR image has correct architecture (linux/amd64)
3. Check security group allows traffic on port 3847

### MCP Client Not Connecting

1. Verify the SSE endpoint is accessible: `curl http://<ALB_DNS>/sse`
2. Check the Authorization header is correct
3. Restart Cursor after updating mcp.json

### Image Architecture Issues

Always build with `--platform linux/amd64` for ECS Fargate:

```bash
docker build --platform linux/amd64 -t opsera-devops-agent:latest .
```
