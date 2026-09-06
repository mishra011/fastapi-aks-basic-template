# FastAPI DevOps Project With Azure Deployment Guide

This project deploys a simple FastAPI application to Azure Kubernetes Service (AKS) using:
- Terraform for infrastructure provisioning
- Azure Container Registry (ACR) for container images
- Docker for containerizing the app
- Kubernetes manifests for deployment and service exposure
- Helm as an optional application deployment path for learning and comparison

## Project Structure

```text
fastapi-devops-project/
├── Dockerfile
├── requirements.txt
├── app/
│   └── main.py
├── infrastructure/
│   ├── kubernetes/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── helm/
│   │   └── fastapi/
│   │       ├── Chart.yaml
│   │       ├── values.yaml
│   │       └── templates/
│   └── terraform/
│       ├── main.tf
│       └── terraform.tfstate
├── scripts/
│   ├── deploy.sh
│   └── deploy-helm.sh
├── docker-compose.yml
└── README.md
```

## 0. Clone the Repository

```bash
git clone https://github.com/mishra011/fastapi-aks.git
cd fastapi-aks
```

## Prerequisites

Make sure you have:
- Azure CLI installed
- Docker installed
- kubectl installed
- Terraform installed
- An Azure subscription

Verify tools:

```bash
az version
terraform version
docker --version
kubectl version --client
```

## 1. Log in to Azure

```bash
az login
az account show -o table
```

If needed, set the subscription:

```bash
az account set --subscription c9228dd2-1a35-4c93-a47c-60f9e28a7aec
```

## 2. Provision Azure Infrastructure with Terraform

Go to the Terraform folder:

```bash
cd ./infrastructure/terraform
```

Initialize and apply Terraform:

```bash
terraform init
terraform apply -auto-approve
```

This creates:
- Azure Resource Group: `fastapi-rg`
- Azure Container Registry: `fastapiacrdm`
- AKS Cluster: `fastapi-aks-cluster-dm`
- AcrPull role assignment for AKS to access ACR

## 3. Get Kubernetes Credentials

```bash
az aks get-credentials --admin --name fastapi-aks-cluster-dm --resource-group fastapi-rg
```

Verify cluster connectivity:

```bash
kubectl get nodes
kubectl get pods
```

## 4. Build Docker Image

From the app root:

```bash
cd ..
```

If you are already in the repository root, you can skip this step.

Login to ACR:

```bash
az acr login --name fastapiacrdm
```

Build the image:

```bash
docker build -t fastapiacrdm.azurecr.io/dmfastapi-app:latest .
```

If your machine is Apple Silicon and your AKS nodes are AMD64, build a multi-arch image:

```bash
docker buildx build --platform linux/amd64 -t fastapiacrdm.azurecr.io/dmfastapi-app:latest --push .
```

Then push it to ACR:

```bash
docker push fastapiacrdm.azurecr.io/dmfastapi-app:latest
```

## 5. Choose How to Deploy the App

After Terraform creates the AKS cluster, you now have two app deployment options so you can learn both approaches side by side.

### Option A: Raw Kubernetes manifests

Go to the Kubernetes manifests folder:

Go to the Kubernetes manifests folder:

```bash
cd ./infrastructure/kubernetes
```

Apply the deployment:

```bash
kubectl apply -f deployment.yaml
```

Apply the service:

```bash
kubectl apply -f service.yaml
```

Check the status:

```bash
kubectl get pods
kubectl get services
```

This path keeps the current learning flow exactly as it is today.

### Option B: Helm chart

Go to the repository root and install or upgrade the Helm release:

```bash
helm upgrade --install fastapi-app ./infrastructure/helm/fastapi
```

You can also override values at deploy time:

```bash
helm upgrade --install fastapi-app ./infrastructure/helm/fastapi \
  --set image.tag=latest \
  --set replicaCount=2 \
  --set service.type=LoadBalancer
```

Or use the helper script:

```bash
./scripts/deploy-helm.sh
```

Use this path when you want to practice Helm templating, release management, and value overrides.

## 6. Verify the Application

Wait for the external IP to be assigned:

```bash
kubectl get services
```

Once the external IP appears, open it in a browser:

```text
http://<external-ip>
```

Example:

```text
http://20.123.45.67/
```

## 7. View Logs

Check pod logs:

```bash
kubectl get pods
kubectl logs <pod-name>
```

Follow logs live:

```bash
kubectl logs -f <pod-name>
```

If deployment is stuck because the image is not pulling, inspect the pod:

```bash
kubectl describe pod <pod-name>
```

## 8. Restart Deployment

```bash
kubectl rollout restart deployment/dmfastapi-app
kubectl rollout status deployment/dmfastapi-app
```

## 9. Local Docker Compose Option

You can also run locally with Docker Compose:

```bash
cd .
docker compose up --build
```

Then visit:

```text
http://localhost:8000
```

## 10. Useful Troubleshooting Commands

```bash
kubectl get pods -o wide
kubectl get svc
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```

If the image fails with an exec format error:

```bash
kubectl logs <pod-name>
```

This usually means the image architecture does not match the AKS node architecture. Rebuild using `docker buildx` for the correct platform.

## Notes

- The app listens on port `8000` inside the container.
- The Kubernetes Service exposes it externally on port `80`.
- The Terraform resource names match the Azure resources in this project and should be kept consistent with the AKS credentials command and the deployment image path.
- The raw files in `infrastructure/kubernetes/` are intentionally kept for learning.
- The Helm chart in `infrastructure/helm/fastapi/` is an additional deployment option, not a replacement.
- Recommended learning split:
  - Use Terraform + raw YAML when learning Kubernetes basics.
  - Use Terraform + Helm when learning packaging, templating, and reusable app deployments.

## Final Deployment Summary

```bash
cd ./infrastructure/terraform
terraform init
terraform apply -auto-approve

cd ../..
az acr login --name fastapiacrdm
docker buildx build --platform linux/amd64 -t fastapiacrdm.azurecr.io/dmfastapi-app:latest --push .

az aks get-credentials --admin --name fastapi-aks-cluster-dm --resource-group fastapi-rg

cd ./infrastructure/kubernetes
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl get pods
kubectl get services
```
