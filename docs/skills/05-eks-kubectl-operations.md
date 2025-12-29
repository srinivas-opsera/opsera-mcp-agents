# Skill: EKS kubectl Operations

## Overview
Working with EKS clusters using kubectl, including authentication, debugging, and common operations.

## Key Learnings

### 1. Configure kubectl for EKS

```bash
# Update kubeconfig for an EKS cluster
aws eks update-kubeconfig \
  --name my-cluster \
  --region us-west-2

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### 2. Check Cluster Status

```bash
# Via AWS CLI
aws eks describe-cluster --name my-cluster \
  --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
  --output table

# Via kubectl
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

### 3. Wait for Cluster to be Active

```bash
# Check status
CLUSTER_STATUS=$(aws eks describe-cluster --name my-cluster \
  --query 'cluster.status' --output text)

if [ "$CLUSTER_STATUS" == "CREATING" ]; then
    echo "Waiting for cluster to become ACTIVE..."
    aws eks wait cluster-active --name my-cluster --region us-west-2
    echo "Cluster is now ACTIVE!"
fi
```

### 4. Namespace Management

```bash
# Create namespace (idempotent)
kubectl create namespace my-namespace --dry-run=client -o yaml | kubectl apply -f -

# Create multiple namespaces
for ns in dev stg prod; do
  kubectl create namespace my-app-${ns} --dry-run=client -o yaml | kubectl apply -f -
done

# List namespaces with pattern
kubectl get ns | grep my-app

# Delete namespace (careful - deletes all resources!)
kubectl delete namespace my-namespace
```

### 5. Service Account for IRSA

```bash
# Create service account with IRSA annotation
kubectl create serviceaccount my-sa -n my-namespace --dry-run=client -o yaml | \
  kubectl apply -f -

# Annotate with IAM role
kubectl annotate serviceaccount my-sa -n my-namespace \
  eks.amazonaws.com/role-arn=arn:aws:iam::123456789:role/my-role \
  --overwrite
```

### 6. Expose Services

```bash
# Patch service to LoadBalancer
kubectl patch svc my-service -n my-namespace \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Get LoadBalancer URL
kubectl get svc my-service -n my-namespace \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Port-forward for local access
kubectl port-forward svc/my-service 8080:80 -n my-namespace
```

### 7. Debugging Pods

```bash
# Get pod status
kubectl get pods -n my-namespace

# Describe pod for events
kubectl describe pod my-pod -n my-namespace

# Get pod logs
kubectl logs my-pod -n my-namespace
kubectl logs my-pod -n my-namespace --previous  # Previous container
kubectl logs my-pod -n my-namespace -f          # Follow logs

# Exec into pod
kubectl exec -it my-pod -n my-namespace -- /bin/sh
```

### 8. Wait for Deployments

```bash
# Wait for deployment to be available
kubectl wait --for=condition=available --timeout=300s \
  deployment/my-deployment -n my-namespace

# Wait for all pods in namespace to be ready
kubectl wait --for=condition=ready pod --all -n my-namespace --timeout=300s
```

### 9. Apply Manifests

```bash
# Apply single file
kubectl apply -f manifest.yaml

# Apply directory
kubectl apply -f ./manifests/

# Apply from URL
kubectl apply -f https://example.com/manifest.yaml

# Apply with namespace override
kubectl apply -f manifest.yaml -n my-namespace

# Dry-run (validate without applying)
kubectl apply -f manifest.yaml --dry-run=client
```

### 10. Get Resources in Various Formats

```bash
# Table format (default)
kubectl get pods

# Wide format (more columns)
kubectl get pods -o wide

# YAML output
kubectl get pod my-pod -o yaml

# JSON output
kubectl get pod my-pod -o json

# JSONPath (extract specific fields)
kubectl get svc my-service -o jsonpath='{.spec.clusterIP}'

# Custom columns
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
```

### 11. Common Troubleshooting

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Check events
kubectl get events -n my-namespace --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -n my-namespace

# Check API server
kubectl api-versions
kubectl api-resources
```

### 12. Secrets Management

```bash
# Get secret value (base64 decode)
kubectl get secret my-secret -n my-namespace \
  -o jsonpath="{.data.password}" | base64 -d

# Create secret from literal
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123 \
  -n my-namespace

# Create secret from file
kubectl create secret generic my-secret \
  --from-file=./credentials.json \
  -n my-namespace
```

## EKS-Specific Commands

```bash
# Get EKS addon versions
aws eks describe-addon-versions --kubernetes-version 1.29

# List installed addons
aws eks list-addons --cluster-name my-cluster

# Get OIDC issuer (for IRSA)
aws eks describe-cluster --name my-cluster \
  --query "cluster.identity.oidc.issuer" --output text

# Get node group status
aws eks describe-nodegroup --cluster-name my-cluster \
  --nodegroup-name my-node-group \
  --query 'nodegroup.{Status:status,DesiredSize:scalingConfig.desiredSize}'
```

## Best Practices

1. **Always specify namespace** with `-n` to avoid mistakes
2. **Use `--dry-run=client`** to validate before applying
3. **Use labels** for filtering: `kubectl get pods -l app=myapp`
4. **Set default namespace**: `kubectl config set-context --current --namespace=my-namespace`
5. **Use aliases** for common commands (add to ~/.bashrc):

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ka='kubectl apply -f'
```

