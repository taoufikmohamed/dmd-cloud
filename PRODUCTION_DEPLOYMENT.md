# Production Deployment Guide

## Prerequisites

1. **Azure CLI** - `az --version`
2. **Terraform** - `terraform --version` (>= 1.0)
3. **kubectl** - `kubectl version --client`
4. **Docker** - `docker --version`
5. **Azure Subscription** with Owner/Contributor access
6. **DeepSeek API Key** from https://platform.deepseek.com/

---

## Deployment Steps

### Phase 1: Infrastructure Provisioning (Azure AKS)

#### 1.1 Login to Azure
```powershell
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

#### 1.2 Deploy Infrastructure with Terraform
```powershell
cd terraform

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -out=tfplan

# Apply infrastructure
terraform apply tfplan

# Save outputs (important!)
terraform output -json > ../outputs.json
```

**Expected Resources Created:**
- Resource Group: `dmd-prod-rg`
- AKS Cluster: `dmd-aks-prod` (3 nodes)
- Azure Container Registry: `dmdacrprod`
- Log Analytics Workspace: `dmd-prod-logs`
- Key Vault: `dmd-kv-prod`

#### 1.3 Connect to AKS
```powershell
# Get credentials
az aks get-credentials --resource-group dmd-prod-rg --name dmd-aks-prod

# Verify connection
kubectl get nodes
```

---

### Phase 2: Build and Push Docker Images

#### 2.1 Login to Azure Container Registry
```powershell
# Get ACR credentials from Terraform output
$ACR_NAME = (terraform output -raw acr_login_server) -replace '\.azurecr\.io', ''
az acr login --name $ACR_NAME
```

#### 2.2 Build and Push Images
```powershell
# Go back to project root
cd ..

# Get full ACR login server
$ACR_SERVER = terraform output -raw acr_login_server

# Build and push webhook-service
docker build -t ${ACR_SERVER}/webhook-service:latest ./webhook_service
docker push ${ACR_SERVER}/webhook-service:latest

# Build and push ai-service
docker build -t ${ACR_SERVER}/ai-service:latest ./ai_service
docker push ${ACR_SERVER}/ai-service:latest

# Verify images
az acr repository list --name $ACR_NAME --output table
```

---

### Phase 3: Kubernetes Configuration

#### 3.1 Update Production Manifests with Your ACR

**CRITICAL: Update image references in:**
- `k8s/production/webhook-deployment.yaml`
- `k8s/production/ai-deployment.yaml`

Replace `dmdacrprod.azurecr.io` with your actual ACR server from:
```powershell
terraform output -raw acr_login_server
```

#### 3.2 Create Namespace
```powershell
kubectl apply -f k8s/production/namespace.yaml
```

#### 3.3 Create Secrets

**Option A: Using Kubernetes Secret (Quick)**
```powershell
kubectl create secret generic ai-service-secrets \
  --from-literal=DEEPSEEK_API_KEY="sk-your-actual-key-here" \
  --namespace=dmd-production \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Option B: Using Azure Key Vault (Recommended for Production)**
```powershell
# Store secret in Key Vault
$KV_NAME = terraform output -raw key_vault_name
az keyvault secret set --vault-name $KV_NAME \
  --name "deepseek-api-key" \
  --value "sk-your-actual-key-here"

# Install Azure Key Vault Provider for Secrets Store CSI Driver
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
  --namespace kube-system

# Apply SecretProviderClass (create this file separately)
```

#### 3.4 Deploy Services
```powershell
# Deploy AI Service (must be first, as webhook depends on it)
kubectl apply -f k8s/production/ai-deployment.yaml

# Wait for AI service to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/ai-service -n dmd-production

# Deploy Webhook Service
kubectl apply -f k8s/production/webhook-deployment.yaml

# Wait for webhook service to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/webhook-service -n dmd-production

# Verify all pods are running
kubectl get pods -n dmd-production
```

---

### Phase 4: Ingress and DNS Setup

#### 4.1 Install NGINX Ingress Controller
```powershell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

#### 4.2 Install cert-manager (for HTTPS/TLS)
```powershell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/cert-manager -n cert-manager
```

#### 4.3 Create Let's Encrypt ClusterIssuer
```powershell
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@domain.com  # UPDATE THIS
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

#### 4.4 Get External IP
```powershell
kubectl get service nginx-ingress-ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

#### 4.5 Configure DNS
Create an A record in your DNS provider:
```
webhook.yourdomain.com  →  <EXTERNAL_IP_FROM_ABOVE>
```

#### 4.6 Update and Apply Ingress
1. Update `k8s/production/ingress.yaml` with your actual domain
2. Apply ingress:
```powershell
kubectl apply -f k8s/production/ingress.yaml
```

#### 4.7 Verify TLS Certificate
```powershell
# Wait for certificate to be issued (may take 2-5 minutes)
kubectl get certificate -n dmd-production

# Should show: READY = True
```

---

### Phase 5: Configure GitHub Webhook

#### 5.1 Get Webhook URL
Your production webhook URL: `https://webhook.yourdomain.com/webhook/github`

#### 5.2 Configure in GitHub Repository
1. Go to your GitHub repository
2. Settings → Webhooks → Add webhook
3. **Payload URL**: `https://webhook.yourdomain.com/webhook/github`
4. **Content type**: `application/json`
5. **Which events**: Just the push event
6. **Active**: ✓
7. Click "Add webhook"

#### 5.3 Test Webhook
Push a commit to your repository and check:
```powershell
# View webhook service logs
kubectl logs -f -l app=webhook-service -n dmd-production

# View AI service logs
kubectl logs -f -l app=ai-service -n dmd-production
```

---

### Phase 6: Monitoring and Operations

#### 6.1 View Application Insights
```powershell
# Get Log Analytics Workspace ID
$WORKSPACE_ID = az monitor log-analytics workspace show \
  --resource-group dmd-prod-rg \
  --workspace-name dmd-prod-logs \
  --query customerId -o tsv

# Query logs in Azure Portal or use CLI
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "ContainerLog | where TimeGenerated > ago(1h) | limit 100"
```

#### 6.2 View Metrics Dashboard
```powershell
# Port-forward to access metrics locally
kubectl port-forward -n dmd-production \
  $(kubectl get pod -n dmd-production -l app=webhook-service -o jsonpath='{.items[0].metadata.name}') \
  9090:9090
```

#### 6.3 Scale Manually (if needed)
```powershell
# Scale webhook service
kubectl scale deployment webhook-service --replicas=5 -n dmd-production

# Scale AI service
kubectl scale deployment ai-service --replicas=4 -n dmd-production
```

#### 6.4 Update Images (Rolling Update)
```powershell
# Build new version
docker build -t ${ACR_SERVER}/webhook-service:v1.1 ./webhook_service
docker push ${ACR_SERVER}/webhook-service:v1.1

# Update deployment
kubectl set image deployment/webhook-service \
  webhook-service=${ACR_SERVER}/webhook-service:v1.1 \
  -n dmd-production

# Watch rollout
kubectl rollout status deployment/webhook-service -n dmd-production

# Rollback if issues occur
kubectl rollout undo deployment/webhook-service -n dmd-production
```

---

## Verification Checklist

- [ ] All pods in Running state: `kubectl get pods -n dmd-production`
- [ ] Services have endpoints: `kubectl get endpoints -n dmd-production`
- [ ] External IP assigned: `kubectl get svc -n dmd-production`
- [ ] Ingress has address: `kubectl get ingress -n dmd-production`
- [ ] TLS certificate issued: `kubectl get certificate -n dmd-production`
- [ ] DNS resolves: `nslookup webhook.yourdomain.com`
- [ ] HTTPS accessible: `curl https://webhook.yourdomain.com/health`
- [ ] GitHub webhook shows green checkmark
- [ ] Logs show no errors
- [ ] HPA is active: `kubectl get hpa -n dmd-production`

---

## Cost Estimation

**Monthly Azure Costs (Approximate):**
- AKS Control Plane: Free
- 3x Standard_D2s_v3 nodes: ~$200-250
- Load Balancer: ~$20
- ACR Standard: ~$20
- Log Analytics: ~$10-30 (depends on data volume)
- **Total: ~$250-320/month**

---

## Troubleshooting

### Pods CrashLooping
```powershell
kubectl describe pod <pod-name> -n dmd-production
kubectl logs <pod-name> -n dmd-production --previous
```

### Cannot Pull Images
```powershell
# Verify ACR access
az aks check-acr --name dmd-aks-prod --resource-group dmd-prod-rg --acr dmdacrprod.azurecr.io
```

### Webhook Not Receiving Requests
```powershell
# Check ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Verify service endpoints
kubectl describe service webhook-service -n dmd-production
```

### High Latency
```powershell
# Check HPA status
kubectl get hpa -n dmd-production

# View pod resource usage
kubectl top pods -n dmd-production
```

---

## Cleanup (Destroy Everything)

```powershell
# Delete Kubernetes resources
kubectl delete namespace dmd-production

# Destroy infrastructure
cd terraform
terraform destroy -auto-approve
```

---

## Security Best Practices

1. **Never commit secrets** - Use Azure Key Vault or Kubernetes Secrets
2. **Enable Azure AD integration** - Already configured in Terraform
3. **Use Network Policies** - Applied in ingress.yaml
4. **Enable Pod Security Standards**
5. **Regular updates** - Keep AKS version updated
6. **Monitor audit logs** - Check Azure Activity Log regularly
7. **Rotate secrets** - Rotate DeepSeek API key periodically
8. **Use private endpoints** - For ACR and Key Vault (additional cost)

---

## Next Steps

1. Set up CI/CD pipeline (GitHub Actions) for automated deployments
2. Configure Azure Monitor alerts for critical metrics
3. Set up backup strategy for Key Vault
4. Implement rate limiting at API Gateway level
5. Add APM (Application Performance Monitoring)
6. Configure Azure Front Door for global distribution
