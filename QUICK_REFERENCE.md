# DMD Cloud - Quick Reference

## 🚀 One-Command Deployment

```powershell
# Automated deployment (recommended)
.\deploy-production.ps1 -DeepSeekApiKey "sk-your-key-here"
```

## 📝 Essential Commands

### Infrastructure
```powershell
# Deploy infrastructure
cd terraform
terraform init
terraform plan
terraform apply

# Get outputs
terraform output acr_login_server
terraform output aks_cluster_name
```

### Docker Images
```powershell
# Build and push
$ACR = "your-acr-name.azurecr.io"
az acr login --name your-acr-name

docker build -t $ACR/webhook-service:latest ./webhook_service
docker push $ACR/webhook-service:latest

docker build -t $ACR/ai-service:latest ./ai_service
docker push $ACR/ai-service:latest
```

### Kubernetes
```powershell
# Connect to cluster
az aks get-credentials --resource-group dmd-prod-rg --name dmd-aks-prod

# Deploy
kubectl apply -f k8s/production/namespace.yaml
kubectl create secret generic ai-service-secrets --from-literal=DEEPSEEK_API_KEY="sk-xxx" -n dmd-production
kubectl apply -f k8s/production/ai-deployment.yaml
kubectl apply -f k8s/production/webhook-deployment.yaml

# Status
kubectl get pods -n dmd-production
kubectl get svc -n dmd-production
kubectl get hpa -n dmd-production

# Logs
kubectl logs -f -l app=webhook-service -n dmd-production
kubectl logs -f -l app=ai-service -n dmd-production

# Scale
kubectl scale deployment webhook-service --replicas=5 -n dmd-production

# Restart
kubectl rollout restart deployment/webhook-service -n dmd-production
kubectl rollout restart deployment/ai-service -n dmd-production
```

### Monitoring
```powershell
# Pod resource usage
kubectl top pods -n dmd-production
kubectl top nodes

# Events
kubectl get events -n dmd-production --sort-by='.lastTimestamp'

# Describe resources
kubectl describe deployment webhook-service -n dmd-production
kubectl describe hpa webhook-service-hpa -n dmd-production
```

### Troubleshooting
```powershell
# Check pod details
kubectl describe pod <pod-name> -n dmd-production

# View previous logs (if pod crashed)
kubectl logs <pod-name> -n dmd-production --previous

# Execute command in pod
kubectl exec -it <pod-name> -n dmd-production -- /bin/sh

# Port forward for local testing
kubectl port-forward svc/webhook-service 8001:8001 -n dmd-production
```

### Ingress & DNS
```powershell
# Get external IP
kubectl get service webhook-service -n dmd-production -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Check ingress
kubectl get ingress -n dmd-production
kubectl describe ingress dmd-ingress -n dmd-production

# Check certificate
kubectl get certificate -n dmd-production
```

## 🔐 Secrets Management

```powershell
# Create secret
kubectl create secret generic ai-service-secrets \
  --from-literal=DEEPSEEK_API_KEY="sk-xxx" \
  -n dmd-production

# Update secret
kubectl delete secret ai-service-secrets -n dmd-production
kubectl create secret generic ai-service-secrets \
  --from-literal=DEEPSEEK_API_KEY="sk-new-key" \
  -n dmd-production

# View secret (base64 encoded)
kubectl get secret ai-service-secrets -n dmd-production -o yaml

# Restart pods to pick up new secret
kubectl rollout restart deployment/ai-service -n dmd-production
```

## 📊 Health Checks

```powershell
# Test webhook service
curl http://<EXTERNAL-IP>:8001/health
curl https://webhook.yourdomain.com/health

# Test from inside pod
kubectl exec -it <webhook-pod> -n dmd-production -- curl http://localhost:8001/health
kubectl exec -it <ai-pod> -n dmd-production -- curl http://localhost:8000/health

# Test GitHub webhook
curl -X POST https://webhook.yourdomain.com/webhook/github \
  -H "Content-Type: application/json" \
  -d '{"repository":{"full_name":"test/repo"},"head_commit":{"id":"abc","message":"test"},"diff":"test"}'
```

## 🔄 Update Deployment

```powershell
# Update image
kubectl set image deployment/webhook-service \
  webhook-service=your-acr.azurecr.io/webhook-service:v1.1 \
  -n dmd-production

# Watch rollout
kubectl rollout status deployment/webhook-service -n dmd-production

# Rollback
kubectl rollout undo deployment/webhook-service -n dmd-production

# Rollback to specific revision
kubectl rollout history deployment/webhook-service -n dmd-production
kubectl rollout undo deployment/webhook-service --to-revision=2 -n dmd-production
```

## 🗑️ Cleanup

```powershell
# Delete application
kubectl delete namespace dmd-production

# Delete infrastructure
cd terraform
terraform destroy

# Or delete resource group (WARNING: deletes everything)
az group delete --name dmd-prod-rg --yes --no-wait
```

## 📍 Important URLs

- **Production Webhook**: `https://webhook.yourdomain.com/webhook/github`
- **Health Endpoint**: `https://webhook.yourdomain.com/health`
- **Azure Portal**: https://portal.azure.com
- **DeepSeek Dashboard**: https://platform.deepseek.com/usage
- **GitHub Webhook Settings**: `https://github.com/<user>/<repo>/settings/hooks`

## 🎯 Health Status Indicators

✅ **Healthy System:**
- All pods in "Running" state
- HPA showing current/desired replicas match
- Ingress has ADDRESS assigned
- Certificate shows READY = True
- GitHub webhook shows green checkmark
- No error logs in past hour

⚠️ **Warning Signs:**
- Pods in "CrashLoopBackOff"
- High CPU/Memory usage (>80%)
- Frequent pod restarts
- 5xx errors in logs
- GitHub webhook shows red X
- Slow response times (>2s)

## 💰 Cost Monitoring

```powershell
# View cost analysis
az consumption usage list \
  --resource-group dmd-prod-rg \
  --start-date 2024-03-01 \
  --end-date 2024-03-31

# Set budget alert (optional)
az consumption budget create \
  --resource-group dmd-prod-rg \
  --budget-name dmd-monthly-budget \
  --amount 500 \
  --time-grain Monthly
```

## 🔔 Set Up Alerts

```powershell
# Create action group for notifications
az monitor action-group create \
  --resource-group dmd-prod-rg \
  --name dmd-alerts \
  --short-name dmdalert \
  --email admin admin@yourdomain.com

# Create CPU alert
az monitor metrics alert create \
  --resource-group dmd-prod-rg \
  --name high-cpu-alert \
  --scopes $(az aks show -g dmd-prod-rg -n dmd-aks-prod --query id -o tsv) \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --action dmd-alerts
```

## 📚 Additional Resources

- Full Deployment Guide: `PRODUCTION_DEPLOYMENT.md`
- Checklist: `DEPLOYMENT_CHECKLIST.md`
- Architecture: `ARCHITECTURE.md`
- User Guide: `README.md`
