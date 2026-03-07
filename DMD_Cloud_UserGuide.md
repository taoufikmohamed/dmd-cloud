# DMD Cloud: Diff-Managed Deployment User Guide

**DMD Cloud** is an automated CI/CD pipeline generator designed to simplify DevOps workflows. By leveraging GitHub webhooks and the DeepSeek AI API, it analyzes code diffs from your pushes and automatically generates optimized GitHub Actions workflows (`.github/workflows/ci-cd.yml`).

---

## 1. Prerequisites
Before bootstrapping the repository, ensure your local environment is equipped with:

*   **Minikube:** For running a local Kubernetes cluster.
*   **kubectl:** The Kubernetes command-line tool.
*   **Docker:** For building container images.
*   **PowerShell:** Recommended for executing the provided automation and test scripts.
*   **DeepSeek API Key:** Obtain yours from the [DeepSeek Platform](https://platform.deepseek.com/).
*   **ngrok (Optional):** Required only if you wish to receive live webhooks from GitHub on your local machine.

---

## 2. Requirements & Setup

### Step 1: Cluster Initialization
Start your local Kubernetes cluster:
```bash
minikube start
```

### Step 2: Configure Secrets
The AI service requires your DeepSeek API key. Create a Kubernetes secret (replace `sk-your-actual-key` with your real key):
```powershell
kubectl create secret generic ai-service-secrets `
  --from-literal=DEEPSEEK_API_KEY="sk-your-actual-key" `
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 3: Build Container Images
Build the core services directly within the Minikube Docker environment:
```powershell
minikube image build -t webhook-service:latest ./webhook_service
minikube image build -t ai-service:latest ./ai_service
```

---

## 3. Execution Steps

### Step 1: Deploy to Kubernetes
Apply the deployment manifests to create the services and pods:
```powershell
kubectl apply -f k8s/webhook-deployment.yaml
kubectl apply -f k8s/ai-deployment.yaml
```
*Verify deployment by running `kubectl get pods` to ensure both services are `Running`.*

### Step 2: Port Forwarding
To interact with the webhook service from your local machine, start a port-forward:
```powershell
kubectl port-forward service/webhook-service 8001:8001
```

### Step 3: Trigger a Test Workflow
Simulate a GitHub push using the provided test script:
```powershell
powershell -File .\test-workflow.ps1
```

### Step 4: Verify Success
Wait approximately 30–40 seconds for the AI to process the diff. Check the logs:
```powershell
kubectl logs -l app=webhook-service --since=2m
```
**Success Indicator:** Look for: `INFO:main:Pipeline saved to: /app/.github/workflows/ci-cd.yml`.

---

## 4. Recommendations for Successful Use

*   **GitHub Integration:** To use with a real repo, set up a GitHub Webhook pointing to your public endpoint (via ngrok) with the path `/webhook/github` and content type `application/json`.
*   **Prompt Customization:** Modify the AI "intelligence" by editing the prompt in `ai_service/main.py` to enforce specific security standards or runner types.
*   **Persistence Warning:** Generated pipelines are saved *inside* the container by default. For production, configure the service to commit files back to Git using a service account.
*   **Timeout Tuning:** For large diffs, increase the `AI_SERVICE_TIMEOUT_SECONDS` environment variable in `k8s/webhook-deployment.yaml`.
*   **Security:** Never commit your `DEEPSEEK_API_KEY`. Always use Kubernetes Secrets for sensitive data.

### Performance Baseline
| Stage | Typical Duration |
| :--- | :--- |
| Webhook Acknowledgment | < 100ms |
| AI Processing (DeepSeek) | 15 - 30s |
| **Total Generation Time** | **~30s** |
