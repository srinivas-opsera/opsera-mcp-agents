#!/usr/bin/env node
/**
 * Opsera DevOps Agent - MCP HTTP/SSE Server
 *
 * This exposes the MCP server via HTTP using SSE transport
 * compatible with Cursor's MCP HTTP client.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import express, { Request, Response } from "express";
import cors from "cors";

const app = express();
app.use(cors());

// Don't parse JSON for /message endpoint - SSE transport needs raw stream
app.use((req, res, next) => {
  if (req.path === "/message") {
    next();
  } else {
    express.json()(req, res, next);
  }
});

const PORT = process.env.PORT || 3847;
const VALID_API_KEY = process.env.VALID_API_KEY || "opsera-dev-key-12345";

// Store active transports by session ID
const transports: Map<string, SSEServerTransport> = new Map();

// =============================================================================
// PROTECTED PROMPTS - Production-ready DevOps expertise
// =============================================================================

const PROTECTED_PROMPTS: Record<string, { description: string; content: string }> = {
  "create-pipeline": {
    description: "Create production-ready CI/CD pipeline with security scanning and multi-environment deployments",
    content: `
# CI/CD Pipeline Generation Expert

You are an expert DevOps engineer specializing in CI/CD pipeline design. Generate production-ready pipelines following industry best practices.

## Analysis Phase

First, analyze the project to understand:
1. **Language & Framework**: Detect from package.json, pom.xml, build.gradle, requirements.txt, go.mod, Cargo.toml, etc.
2. **Build Tools**: npm, yarn, maven, gradle, pip, go build, cargo, etc.
3. **Test Frameworks**: jest, pytest, junit, go test, etc.
4. **Existing CI/CD**: Check for existing .github/workflows, .gitlab-ci.yml, Jenkinsfile
5. **Deployment Artifacts**: Docker, JAR, binary, static files

## Pipeline Stages (Required)

### 1. Build Stage
- Install dependencies with caching
- Compile/transpile code
- Generate artifacts

### 2. Test Stage
- Unit tests with coverage reporting (minimum 80% coverage)
- Integration tests (if applicable)
- Fail fast on test failures

### 3. Security Stage
- SAST scanning (CodeQL, Semgrep, or SonarQube)
- Dependency vulnerability scanning (npm audit, safety, trivy)
- Secrets detection (gitleaks, trufflehog)
- Container scanning (if Docker)

### 4. Build Artifact Stage
- Docker image build with multi-stage builds
- Tag with git SHA and semantic version
- Push to registry (conditionally on main/release branches)

### 5. Deploy Stage
- Environment-specific deployments (dev, staging, prod)
- Manual approval gates for production
- Rollback capability
- Health checks post-deployment

## Platform-Specific Best Practices

### GitHub Actions
- Use specific action versions (e.g., actions/checkout@v4)
- Implement concurrency controls to cancel outdated runs
- Use GITHUB_TOKEN for authentication
- Cache dependencies with actions/cache
- Use matrix builds for multi-version testing
- Implement OIDC for cloud deployments (no long-lived secrets)

### GitLab CI
- Use rules: instead of only/except
- Implement DAG for parallel stages
- Use extends: for DRY configurations
- Configure artifacts with proper expiration
- Use GitLab environments for deployments

### Jenkins
- Use declarative pipeline syntax
- Implement shared libraries for reusability
- Configure agent labels properly
- Use credentials binding for secrets
- Implement proper cleanup in post blocks

### Azure DevOps
- Use template references for reusability
- Implement service connections securely
- Use variable groups for environment configs
- Configure proper agent pools

## Output Requirements

1. Create the pipeline file in the correct location (.github/workflows/, .gitlab-ci.yml, Jenkinsfile)
2. Include inline comments explaining each section
3. Ensure all secrets use proper secret management (never hardcode)
4. Include status badge in README
5. Add pipeline documentation
    `.trim(),
  },

  "security-audit": {
    description: "Comprehensive security audit with SAST, dependency scanning, and compliance framework mapping",
    content: `
# Security Audit Expert

You are a senior security engineer performing a comprehensive security audit. Execute thorough security scans and provide actionable remediation guidance.

## Scan Execution

### 1. Secrets Detection
Run gitleaks to detect hardcoded secrets:
\`\`\`bash
gitleaks detect --source . --report-format json --report-path gitleaks-report.json
\`\`\`

Common patterns to detect:
- API keys (AWS, GCP, Azure, Stripe, etc.)
- Database connection strings
- Private keys and certificates
- OAuth tokens and JWT secrets
- Password patterns

### 2. Dependency Vulnerability Scanning

**For Node.js:**
\`\`\`bash
npm audit --json > npm-audit.json
\`\`\`

**For Python:**
\`\`\`bash
pip install safety
safety check --json > safety-report.json
\`\`\`

**For Container Images:**
\`\`\`bash
trivy fs --format json --output trivy-report.json .
\`\`\`

### 3. Infrastructure-as-Code Scanning
\`\`\`bash
checkov -d . --output-file checkov-report.json --output json
\`\`\`

Checks for:
- Terraform misconfigurations
- Kubernetes manifest issues
- Docker security issues
- CloudFormation problems

### 4. Dockerfile Linting
\`\`\`bash
hadolint Dockerfile --format json > hadolint-report.json
\`\`\`

## Compliance Framework Mapping

### SOC2
- CC6.1: Logical access controls
- CC6.6: System boundary protections
- CC6.7: Data transmission protection
- CC7.1: System monitoring
- CC7.2: Anomaly detection

### HIPAA
- 164.312(a)(1): Access controls
- 164.312(b): Audit controls
- 164.312(c)(1): Integrity controls
- 164.312(d): Authentication
- 164.312(e)(1): Transmission security

### PCI-DSS
- Req 2: Secure configurations
- Req 3: Protect stored data
- Req 4: Encrypt transmissions
- Req 6: Secure development
- Req 10: Track and monitor access

## Report Format

### Executive Summary
- Total findings by severity (Critical, High, Medium, Low)
- Risk score (1-100)
- Compliance status per framework

### Detailed Findings
For each finding:
1. **Severity**: Critical/High/Medium/Low
2. **Category**: Secrets/Vulnerabilities/Misconfiguration/Compliance
3. **Location**: File path and line number
4. **Description**: What was found
5. **Impact**: Potential security impact
6. **Remediation**: Step-by-step fix instructions
7. **References**: CVE, CWE, or compliance control IDs

### Remediation Priority
1. Critical: Fix immediately (exposed secrets, RCE vulnerabilities)
2. High: Fix within 24 hours (auth bypass, SQL injection)
3. Medium: Fix within 1 week (XSS, info disclosure)
4. Low: Fix within 1 month (best practice violations)
    `.trim(),
  },

  "k8s-deploy": {
    description: "Production Kubernetes deployment with security hardening, autoscaling, and observability",
    content: `
# Kubernetes Deployment Expert

You are a Kubernetes expert creating production-ready deployment configurations. Apply cloud-native best practices and security hardening.

## Analysis Phase

Analyze the application to determine:
1. **Application Type**: Web service, API, worker, cron job
2. **Port Requirements**: HTTP/HTTPS ports, gRPC, custom protocols
3. **Resource Needs**: CPU, memory based on application type
4. **Storage**: Persistent volumes, config files, secrets
5. **Dependencies**: Databases, caches, message queues
6. **Scaling**: Expected load patterns, burst requirements

## Required Kubernetes Resources

### 1. Deployment
\`\`\`yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {app-name}
  labels:
    app: {app-name}
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: {app-name}
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: {app-name}
        image: {image}:{tag}
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
\`\`\`

### 2. Service, HPA, PDB, NetworkPolicy
Include all supporting resources for production:
- Service for networking
- HorizontalPodAutoscaler (70% CPU target)
- PodDisruptionBudget (minAvailable: 2)
- NetworkPolicy for zero-trust networking

## Directory Structure (Kustomize)
\`\`\`
k8s/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    ├── staging/
    └── production/
\`\`\`

## Security Requirements
1. Non-root containers
2. Read-only filesystem (mount writable volumes only where needed)
3. Resource limits (prevent resource exhaustion)
4. Network policies (zero-trust networking)
5. External secrets (use sealed-secrets or external-secrets-operator)
6. Distroless or minimal base images
    `.trim(),
  },

  "dora-report": {
    description: "Generate comprehensive DORA metrics report with performance analysis and improvement recommendations",
    content: `
# DORA Metrics Analysis Expert

You are a DevOps metrics expert analyzing engineering performance using DORA (DevOps Research and Assessment) metrics. Provide data-driven insights and actionable recommendations.

## Data Collection Commands

### 1. Deployment Frequency
\`\`\`bash
# Count deployments/releases in last 90 days
git log --oneline --since="90 days ago" --grep="deploy\\|release\\|Merge pull request" | wc -l

# List recent tags
git tag --list --sort=-creatordate | head -20
\`\`\`

### 2. Lead Time for Changes
\`\`\`bash
# Get merged PRs with timestamps
git log --merges --since="90 days ago" --format="%H %ci %s"

# Calculate time from first commit to merge
git log --format="%ci" <merge-sha>^..<merge-sha> | tail -1
\`\`\`

### 3. Change Failure Rate
\`\`\`bash
# Count reverts and hotfixes
git log --oneline --since="90 days ago" --grep="revert\\|hotfix\\|rollback\\|fix.*prod" | wc -l

# Total deployments for rate calculation
git log --oneline --since="90 days ago" --grep="deploy\\|release" | wc -l
\`\`\`

### 4. Mean Time to Recovery (MTTR)
\`\`\`bash
# Find incidents and their fixes
git log --oneline --since="90 days ago" --grep="revert\\|hotfix" --format="%H %ci %s"
\`\`\`

## DORA Performance Categories

| Category | Deploy Freq | Lead Time | Change Failure | MTTR |
|----------|-------------|-----------|----------------|------|
| **Elite** | Multiple/day | < 1 hour | 0-15% | < 1 hour |
| **High** | Daily-Weekly | 1 day - 1 week | 16-30% | < 1 day |
| **Medium** | Weekly-Monthly | 1 week - 1 month | 16-30% | < 1 week |
| **Low** | Monthly+ | > 1 month | 16-30% | > 1 month |

## Report Structure

### Executive Summary
- Overall DORA performance category
- Trend comparison (vs previous quarter)
- Top 3 improvement opportunities

### Detailed Metrics

#### Deployment Frequency
- Total deployments in period
- Average deployments per week
- Deployment pattern analysis (weekday vs weekend)
- Trend over time

#### Lead Time for Changes
- Average lead time
- P50, P90, P99 percentiles
- Breakdown by change type (feature, bugfix, hotfix)
- Bottleneck identification

#### Change Failure Rate
- Failure rate percentage
- Failure categories (bugs, config, infrastructure)
- Impact severity distribution
- Root cause patterns

#### Mean Time to Recovery
- Average MTTR
- P50, P90, P99 percentiles
- Recovery patterns
- Incident response analysis

### Improvement Recommendations

#### To Improve Deployment Frequency
1. Implement trunk-based development
2. Automate deployment pipelines completely
3. Use feature flags for safer releases
4. Reduce batch sizes (smaller PRs)
5. Automate testing to reduce manual gates

#### To Reduce Lead Time
1. Implement automated testing (unit, integration, e2e)
2. Streamline code review process (< 24 hour SLA)
3. Use parallel pipeline stages
4. Automate security scanning in CI
5. Remove manual approval bottlenecks

#### To Reduce Change Failure Rate
1. Implement comprehensive test coverage (>80%)
2. Use canary deployments
3. Add pre-production environments
4. Improve monitoring and alerting
5. Implement feature flags for gradual rollouts

#### To Reduce MTTR
1. Implement automated rollbacks
2. Improve observability (logs, metrics, traces)
3. Create runbooks for common issues
4. Practice incident response with game days
5. Implement on-call rotations with clear escalation

## Benchmarking

Compare against:
- Industry averages for your sector
- Previous quarters (trend analysis)
- Elite performer targets
- Team-specific improvement goals

Now analyze this repository and provide the DORA metrics report.
    `.trim(),
  },
};

// =============================================================================
// PROTECTED TOOLS
// =============================================================================

const PROTECTED_TOOLS = [
  {
    name: "opsera_create_pipeline",
    description: "Create a production-ready CI/CD pipeline",
    inputSchema: {
      type: "object" as const,
      properties: {
        platform: {
          type: "string",
          description: "CI/CD platform (github-actions, gitlab-ci, jenkins, azure-devops)",
          enum: ["github-actions", "gitlab-ci", "jenkins", "azure-devops"],
        },
        language: {
          type: "string",
          description: "Programming language (auto-detected if not specified)",
        },
        deployment_target: {
          type: "string",
          description: "Deployment target (kubernetes, docker, serverless, vm)",
        },
      },
      required: ["platform"],
    },
  },
  {
    name: "opsera_security_scan",
    description: "Run comprehensive security scan with compliance mapping",
    inputSchema: {
      type: "object" as const,
      properties: {
        scan_type: {
          type: "string",
          description: "Type of security scan",
          enum: ["full", "secrets", "vulnerabilities", "compliance"],
        },
        compliance_framework: {
          type: "string",
          description: "Compliance framework to map findings against",
          enum: ["soc2", "hipaa", "pci-dss", "iso27001"],
        },
      },
      required: ["scan_type"],
    },
  },
  {
    name: "opsera_dora_metrics",
    description: "Generate DORA metrics report with recommendations",
    inputSchema: {
      type: "object" as const,
      properties: {
        period_days: {
          type: "number",
          description: "Analysis period in days (default: 90)",
          default: 90,
        },
      },
    },
  },
];

// =============================================================================
// AUTHENTICATION
// =============================================================================

function authenticate(req: Request, res: Response, next: () => void) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing API key" });
    return;
  }

  const apiKey = authHeader.substring(7);

  if (apiKey !== VALID_API_KEY) {
    res.status(401).json({ error: "Invalid API key" });
    return;
  }

  next();
}

// =============================================================================
// MCP SERVER FACTORY
// =============================================================================

function createMCPServer(): Server {
  const server = new Server(
    { name: "opsera-devops-agent", version: "1.0.0" },
    { capabilities: { tools: {}, prompts: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return { tools: PROTECTED_TOOLS };
  });

  server.setRequestHandler(ListPromptsRequestSchema, async () => {
    const prompts = Object.entries(PROTECTED_PROMPTS).map(([name, data]) => ({
      name,
      description: data.description,
    }));
    return { prompts };
  });

  server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    const { name } = request.params;
    const prompt = PROTECTED_PROMPTS[name];

    if (!prompt) {
      throw new Error(`Prompt not found: ${name}`);
    }

    return {
      messages: [
        {
          role: "user" as const,
          content: { type: "text" as const, text: prompt.content },
        },
      ],
    };
  });

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    switch (name) {
      case "opsera_create_pipeline": {
        const platform = (args as any)?.platform || "github-actions";
        const language = (args as any)?.language || "auto-detect";
        const target = (args as any)?.deployment_target || "kubernetes";

        return {
          content: [{
            type: "text" as const,
            text: `# CI/CD Pipeline Generation

## Configuration
- **Platform**: ${platform}
- **Language**: ${language}
- **Deployment Target**: ${target}

${PROTECTED_PROMPTS["create-pipeline"].content}

---
Now analyze this project and generate a production-ready ${platform} pipeline.`,
          }],
        };
      }

      case "opsera_security_scan": {
        const scanType = (args as any)?.scan_type || "full";
        const framework = (args as any)?.compliance_framework;

        return {
          content: [{
            type: "text" as const,
            text: `# Security Scan

## Configuration
- **Scan Type**: ${scanType}
- **Compliance Framework**: ${framework || "None specified"}

${PROTECTED_PROMPTS["security-audit"].content}

---
Now execute the security scan and provide a detailed report.`,
          }],
        };
      }

      case "opsera_dora_metrics": {
        const periodDays = (args as any)?.period_days || 90;

        return {
          content: [{
            type: "text" as const,
            text: `# DORA Metrics Analysis

## Configuration
- **Analysis Period**: ${periodDays} days

${PROTECTED_PROMPTS["dora-report"].content}`,
          }],
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  });

  return server;
}

// =============================================================================
// HTTP ENDPOINTS
// =============================================================================

app.get("/health", (_req, res) => {
  res.json({ status: "ok", version: "1.0.0", server: "opsera-devops-agent" });
});

app.get("/sse", authenticate, async (req: Request, res: Response) => {
  console.log("New SSE connection");
  
  const transport = new SSEServerTransport("/message", res);
  transports.set(transport.sessionId, transport);
  console.log(`Session created: ${transport.sessionId}`);

  const server = createMCPServer();

  res.on("close", () => {
    console.log(`Session closed: ${transport.sessionId}`);
    transports.delete(transport.sessionId);
  });

  await server.connect(transport);
});

app.post("/message", authenticate, async (req: Request, res: Response) => {
  const sessionId = req.query.sessionId as string;
  
  if (!sessionId) {
    res.status(400).json({ error: "Missing sessionId" });
    return;
  }

  const transport = transports.get(sessionId);
  
  if (!transport) {
    res.status(400).json({ error: "Invalid session" });
    return;
  }

  await transport.handlePostMessage(req, res);
});

// Legacy REST endpoints
app.post("/tools", authenticate, (_req, res) => {
  res.json({ tools: PROTECTED_TOOLS });
});

app.post("/prompts", authenticate, (_req, res) => {
  const prompts = Object.entries(PROTECTED_PROMPTS).map(([name, data]) => ({
    name,
    description: data.description,
  }));
  res.json({ prompts });
});

app.post("/prompts/get", authenticate, (req, res) => {
  const { name } = req.body;
  const prompt = PROTECTED_PROMPTS[name];

  if (!prompt) {
    res.status(404).json({ error: `Prompt not found: ${name}` });
    return;
  }

  res.json({
    messages: [{
      role: "user",
      content: { type: "text", text: prompt.content },
    }],
  });
});

app.post("/tools/call", authenticate, (req, res) => {
  const { name, arguments: args } = req.body;

  const prompt = name === "opsera_create_pipeline" ? "create-pipeline" :
                 name === "opsera_security_scan" ? "security-audit" :
                 name === "opsera_dora_metrics" ? "dora-report" : null;

  if (!prompt || !PROTECTED_PROMPTS[prompt]) {
    res.status(404).json({ error: `Unknown tool: ${name}` });
    return;
  }

  res.json({
    content: [{
      type: "text",
      text: PROTECTED_PROMPTS[prompt].content,
    }],
  });
});

// =============================================================================
// START SERVER
// =============================================================================

app.listen(PORT, () => {
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║  Opsera DevOps Agent - MCP Server                            ║
╠══════════════════════════════════════════════════════════════╣
║  Port: ${PORT}                                                  ║
║  SSE:  GET  /sse                                             ║
║  Msg:  POST /message                                         ║
╠══════════════════════════════════════════════════════════════╣
║  Tools: opsera_create_pipeline, opsera_security_scan,        ║
║         opsera_dora_metrics                                  ║
╚══════════════════════════════════════════════════════════════╝
  `);
});
