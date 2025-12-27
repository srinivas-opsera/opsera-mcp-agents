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
                                    │ HTTPS/SSE Connection (Authenticated)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS Infrastructure                             │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Route 53 DNS (mcp-agent.opsera.io)                               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│                                    ▼                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Application Load Balancer (HTTPS with ACM Certificate)          │  │
│  │  - Idle timeout: 300s (for SSE connections)                       │  │
│  │  - HTTP → HTTPS redirect                                          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│                                    ▼                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  ECS Fargate Service (Auto-scaling)                               │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Opsera DevOps Agent MCP Server                             │  │  │
│  │  │  - SSE Transport with heartbeat (25s keepalive)             │  │  │
│  │  │  - Protected prompts & tools                                │  │  │
│  │  │  - API Key authentication                                   │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed
- Terraform installed (>= 1.0)
- Node.js 20+
- Route 53 Hosted Zone (for custom domain)

## Quick Start

### 1. Clone and Build

```bash
# Install dependencies
npm install

# Build
npm run build
```

### 2. Configure Terraform

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Required
aws_region = "us-east-1"
vpc_id     = "vpc-xxxxxxxxx"
api_key    = "your-secure-api-key"  # Generate: openssl rand -hex 32

# Route 53 / Custom Domain (Recommended)
domain_name        = "mcp-agent.opsera.io"
hosted_zone_id     = "Z1234567890ABC"
create_certificate = true
alb_idle_timeout   = 300
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform apply
```

### 4. Deploy Application

```bash
./scripts/deploy.sh
```

## Opsera Pipeline (CI/CD)

This project uses **Opsera** for automated CI/CD pipelines.

### Pipeline Features

| Feature | Description |
|---------|-------------|
| **Auto-Trigger** | Runs on push to `main`, `develop`, `release/*` branches |
| **Path Filters** | Triggers on changes to `src/**`, `infrastructure/**`, `Dockerfile`, `package.json` |
| **Security Scanning** | Gitleaks, npm audit, Semgrep, Checkov |
| **Docker Build** | Multi-stage build, ECR push |
| **Infrastructure** | Terraform plan/apply for infra changes |
| **Multi-Environment** | dev → staging → production (with approvals) |
| **DORA Metrics** | Automatic tracking of deployment frequency, lead time, etc. |

### Setup Opsera Pipeline

```bash
# Run setup script
./scripts/setup-opsera-pipeline.sh
```

Or manually import `opsera-pipeline.json` to the Opsera platform.

### Required Secrets (Configure in Opsera)

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key for ECR/ECS |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `VALID_API_KEY` | MCP server authentication key |
| `SLACK_WEBHOOK_URL` | (Optional) Slack notifications |

### Deployment Flow

```
Code Push → Opsera Pipeline Triggers
    ↓
┌─────────────────────────────────────────────────────────┐
│ Build Stage                                              │
│ - npm install, npm run build                            │
└─────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────┐
│ Test + Security Stage (Parallel)                        │
│ - TypeScript check, Unit tests                          │
│ - Gitleaks, npm audit, Semgrep, Checkov                │
└─────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────┐
│ Docker Build Stage                                       │
│ - Build linux/amd64 image                               │
│ - Push to ECR with git SHA tag                          │
│ - Trivy container scan                                  │
└─────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────┐
│ Infrastructure Stage (if infrastructure/** changed)     │
│ - Terraform init, plan, apply                           │
└─────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────┐
│ Deploy: Development (Auto)                               │
│ - Update ECS service                                    │
│ - Health check                                          │
└─────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────┐
│ Deploy: Staging (Auto after Dev)                         │
│ - Update ECS service                                    │
│ - Health check                                          │
└─────────────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────────────┐
│ Deploy: Production (Manual Approval Required)            │
│ - Update ECS service                                    │
│ - Health check + Smoke test                             │
└─────────────────────────────────────────────────────────┘
```

## Route 53 DNS Setup

### Option 1: Automatic (Terraform)

Set these variables in `terraform.tfvars`:

```hcl
domain_name        = "mcp-agent.opsera.io"
hosted_zone_id     = "Z1234567890ABC"  # Your Route 53 Hosted Zone ID
create_certificate = true
```

Terraform will automatically:
1. Create ACM certificate
2. Add DNS validation records
3. Wait for certificate validation
4. Create Route 53 A record (alias to ALB)
5. Configure HTTPS listener

### Option 2: Manual

1. **Create ACM Certificate:**
   - Go to AWS Certificate Manager
   - Request public certificate for your domain
   - Complete DNS validation

2. **Add Route 53 Record:**
   - Go to Route 53 → Hosted Zones → Your zone
   - Create A record with alias to ALB

3. **Update Terraform:**
   ```hcl
   create_certificate = false
   certificate_arn    = "arn:aws:acm:us-east-1:xxx:certificate/xxx"
   ```

## Cursor MCP Configuration

Add to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "opsera-devops-agent": {
      "type": "sse",
      "url": "https://mcp-agent.opsera.io/sse",
      "headers": {
        "Authorization": "Bearer YOUR_API_KEY"
      }
    }
  }
}
```

**Important:** Restart Cursor after updating the configuration.

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Health check |
| `/sse` | GET | Yes | SSE connection for MCP protocol |
| `/message` | POST | Yes | Message endpoint for MCP protocol |

## Available Tools

| Tool | Description |
|------|-------------|
| `opsera_create_pipeline` | Create production-ready CI/CD pipelines |
| `opsera_security_scan` | Run security scans with compliance mapping |
| `opsera_dora_metrics` | Generate DORA metrics reports |

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

# Run HTTP server in development mode
npm run dev:http

# Build for production
npm run build

# Run production HTTP server
npm run start:http
```

## Troubleshooting

### SSE Connection Dropping

The server now includes:
- **Heartbeat mechanism** - Sends keepalive every 25 seconds
- **ALB timeout** - Configured to 300 seconds (5 minutes)

If connections still drop:
1. Check ALB idle timeout in AWS Console
2. Verify no proxy is buffering SSE responses
3. Check CloudWatch logs for errors

### ECS Tasks Not Starting

1. Check CloudWatch logs: `/ecs/opsera-devops-agent`
2. Verify ECR image has correct architecture (linux/amd64)
3. Check security group allows traffic on port 3847

### Certificate Validation Pending

1. Go to ACM in AWS Console
2. Check if DNS validation records exist in Route 53
3. Wait up to 30 minutes for propagation

### MCP Client Not Connecting

1. Verify the SSE endpoint is accessible: 
   ```bash
   curl https://mcp-agent.opsera.io/health
   ```
2. Check the Authorization header is correct
3. Restart Cursor after updating mcp.json

### Image Architecture Issues

Always build with `--platform linux/amd64` for ECS Fargate:

```bash
docker build --platform linux/amd64 -t opsera-devops-agent:latest .
```

## Security Considerations

1. **API Key Rotation** - Rotate keys regularly using AWS Secrets Manager
2. **VPC Configuration** - Consider using private subnets with NAT Gateway
3. **WAF** - Add AWS WAF for additional protection
4. **Logging** - All requests logged to CloudWatch
5. **Certificate** - TLS 1.3 enforced via ALB security policy
