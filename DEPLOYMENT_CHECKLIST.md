# Production Deployment - What Needs to be Updated

## ✅ COMPLETED
These files have been created/updated for production:

1. **Terraform Infrastructure** - `terraform/main.tf`
   - Production-grade AKS cluster (3 nodes, autoscaling)
   - Azure Container Registry (ACR)
   - Log Analytics Workspace
   - Azure Key Vault
   - Proper networking and RBAC

2. **Production Kubernetes Manifests** - `k8s/production/`
   - `namespace.yaml` - Production namespace with resource quotas
   - `webhook-deployment.yaml` - 3 replicas, HPA, production resources
   - `ai-deployment.yaml` - 2 replicas, HPA, production resources
   - `ingress.yaml` - NGINX ingress with TLS/SSL support

3. **Deployment Documentation** - `PRODUCTION_DEPLOYMENT.md`
   - Complete step-by-step deployment guide
   - Phase-by-phase instructions
   - Troubleshooting section
   - Cost estimates

4. **Automated Deployment Script** - `deploy-production.ps1`
   - One-command deployment
   - Automated infrastructure provisioning
   - Image building and pushing
   - Kubernetes deployment

5. **CI/CD Pipeline** - `.github/workflows/deploy-production.yml`
   - Automated deployments on push to main
   - Build and push Docker images
   - Deploy to AKS
   - Health checks and rollback

---

## 🔧 REQUIRED UPDATES (Before Deployment)

### 1. Configuration Files

#### `k8s/production/webhook-deployment.yaml` (Line 21)
```yaml
image: YOUR_ACR_NAME.azurecr.io/webhook-service:latest  # REPLACE
```
→ Update after running Terraform (example: `dmdacrprod.azurecr.io/webhook-service:latest`)

#### `k8s/production/ai-deployment.yaml` (Line 21)
```yaml
image: YOUR_ACR_NAME.azurecr.io/ai-service:latest  # REPLACE
```
→ Update after running Terraform

#### `k8s/production/ingress.yaml` (Lines 19, 24)
```yaml
- hosts:
  - webhook.yourdomain.com  # REPLACE WITH YOUR DOMAIN
```
→ Replace with actual domain (e.g., `webhook.mycompany.com`)

#### `.github/workflows/deploy-production.yml` (Lines 10-12)
```yaml
env:
  AZURE_RESOURCE_GROUP: dmd-prod-rg  # VERIFY
  AKS_CLUSTER_NAME: dmd-aks-prod     # VERIFY
  ACR_NAME: dmdacrprod               # VERIFY
```
→ Update after running Terraform if names differ

---

### 2. GitHub Secrets (Required for CI/CD)

Go to: **Repository Settings → Secrets and variables → Actions → New repository secret**

Add these secrets:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AZURE_CREDENTIALS` | Azure Service Principal | See instructions below |
| `ACR_USERNAME` | ACR admin username | `terraform output -raw acr_admin_username` |
| `ACR_PASSWORD` | ACR admin password | `terraform output -raw acr_admin_password` |

**Getting AZURE_CREDENTIALS:**
```powershell
# Create service principal
az ad sp create-for-rbac --name "dmd-github-actions" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/dmd-prod-rg \
  --sdk-auth

# Copy the entire JSON output and paste as AZURE_CREDENTIALS secret
```

---

### 3. DNS Configuration

After deployment, you'll get an external IP address. Configure DNS:

1. Get external IP:
```powershell
kubectl get service webhook-service -n dmd-production -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

2. Create DNS A record in your domain provider:
```
Type: A
Name: webhook
Value: <EXTERNAL_IP>
TTL: 300
```

3. Verify DNS propagation:
```powershell
nslookup webhook.yourdomain.com
```

---

### 4. Let's Encrypt ClusterIssuer (For HTTPS)

Create after deploying cert-manager:

```powershell
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@yourdomain.com  # REPLACE WITH YOUR EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

---

### 5. GitHub Webhook Configuration

After deployment and DNS setup:

1. Go to your GitHub repository
2. **Settings → Webhooks → Add webhook**
3. Configure:
   - **Payload URL**: `https://webhook.yourdomain.com/webhook/github`
   - **Content type**: `application/json`
   - **Secret**: (optional, recommended for production)
   - **SSL verification**: Enable SSL verification
   - **Which events**: Just the push event
   - **Active**: ✓

---

### 6. Environment Variables Check

Ensure you have:

- **DeepSeek API Key**: Get from https://platform.deepseek.com/
- **Azure Subscription ID**: `az account show --query id -o tsv`

---

## 📋 DEPLOYMENT CHECKLIST

### Pre-Deployment
- [ ] Azure CLI installed and logged in
- [ ] Terraform installed (>= 1.0)
- [ ] kubectl installed
- [ ] Docker installed and running
- [ ] DeepSeek API key obtained
- [ ] Azure subscription selected

### Infrastructure
- [ ] Run `terraform init` in terraform/
- [ ] Run `terraform plan` to review changes
- [ ] Run `terraform apply` to create resources
- [ ] Note down ACR server name from outputs
- [ ] Note down AKS cluster name from outputs

### Images
- [ ] Update ACR name in k8s/production/*.yaml files
- [ ] Build webhook-service Docker image
- [ ] Build ai-service Docker image
- [ ] Push both images to ACR
- [ ] Verify images in ACR: `az acr repository list`

### Kubernetes
- [ ] Connect to AKS: `az aks get-credentials`
- [ ] Create namespace: `kubectl apply -f k8s/production/namespace.yaml`
- [ ] Create secrets with DeepSeek API key
- [ ] Deploy AI service
- [ ] Verify AI service is running
- [ ] Deploy webhook service
- [ ] Verify webhook service is running

### Networking
- [ ] Install NGINX Ingress Controller
- [ ] Install cert-manager
- [ ] Create Let's Encrypt ClusterIssuer (update email)
- [ ] Get external IP address
- [ ] Configure DNS A record
- [ ] Update domain in ingress.yaml
- [ ] Apply ingress: `kubectl apply -f k8s/production/ingress.yaml`
- [ ] Wait for TLS certificate (2-5 minutes)
- [ ] Verify HTTPS: `curl https://webhook.yourdomain.com/health`

### GitHub Integration
- [ ] Create Azure service principal for GitHub Actions
- [ ] Add AZURE_CREDENTIALS to GitHub secrets
- [ ] Add ACR_USERNAME to GitHub secrets
- [ ] Add ACR_PASSWORD to GitHub secrets
- [ ] Configure webhook in GitHub repository
- [ ] Test webhook with a push

### Monitoring
- [ ] Verify all pods running: `kubectl get pods -n dmd-production`
- [ ] Check HPA status: `kubectl get hpa -n dmd-production`
- [ ] View logs: `kubectl logs -l app=webhook-service -n dmd-production`
- [ ] Test end-to-end: push code and verify pipeline generation

### Optional (Recommended)
- [ ] Set up Azure Monitor alerts
- [ ] Configure backup for Key Vault
- [ ] Enable Azure Defender for Kubernetes
- [ ] Set up log retention policies
- [ ] Document emergency procedures

---

## 🚀 QUICK START

**Option 1: Manual Deployment (Recommended for first time)**
Follow the detailed guide in `PRODUCTION_DEPLOYMENT.md`

**Option 2: Automated Script**
```powershell
.\deploy-production.ps1 -DeepSeekApiKey "sk-your-key-here" -AzureSubscriptionId "your-sub-id"
```

**Option 3: CI/CD (After manual setup once)**
Just push to main branch - GitHub Actions will handle deployment

---

## 📊 Expected Results

After successful deployment:

1. **Infrastructure**: AKS cluster with 3 nodes running
2. **Services**: 
   - 3 webhook-service pods
   - 2 ai-service pods
   - All pods in "Running" state
3. **Network**: External IP assigned, DNS resolving, HTTPS working
4. **GitHub**: Webhook shows green checkmark after push
5. **Logs**: Pipeline generation logs visible in webhook service

---

## 🆘 NEED HELP?

Common issues and solutions are in `PRODUCTION_DEPLOYMENT.md` troubleshooting section.

For support:
1. Check pod logs: `kubectl logs -f <pod-name> -n dmd-production`
2. Check pod status: `kubectl describe pod <pod-name> -n dmd-production`
3. Check events: `kubectl get events -n dmd-production --sort-by='.lastTimestamp'`
