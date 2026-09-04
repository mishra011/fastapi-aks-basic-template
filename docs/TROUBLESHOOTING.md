# GitHub Actions + Azure AKS Troubleshooting Guide

This guide captures the CI/CD issues resolved on September 3, 2026 for this repository and the exact fixes that worked.

It is written for the current setup in [deploy.yml](/Users/deepakmishra/work_2026/fastapi-base-test/.github/workflows/deploy.yml), which deploys the app to AKS from the `main` branch using GitHub Actions, Azure OIDC login, ACR, and `kubectl`.

## Current Working Setup

Repository:

```text
https://github.com/mishra011/fastapi-aks-basic-template
```

Azure app registration used by GitHub Actions:

```text
fastapi-aks-github-actions
```

Known Azure values:

```text
AZURE_TENANT_ID=edcd38cf-af3a-402e-aa86-3d20f2e7e7b6
AZURE_SUBSCRIPTION_ID=c9228dd2-1a35-4c93-a47c-60f9e28a7aec
AZURE_CLIENT_ID=<from app registration fastapi-aks-github-actions>
```

AKS and ACR resources:

```text
Resource group: fastapi-rg
AKS cluster: fastapi-aks-cluster-dm
ACR: fastapiacrdm
Image: dmfastapi-app
```

Public app URL found during verification:

```text
http://48.206.249.238
```

## Current Workflow Behavior

The workflow currently:

1. Triggers only on pushes to `main`
2. Logs into Azure using OIDC and these GitHub secrets:
   `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
3. Logs into ACR
4. Builds and pushes the Docker image
5. Uses non-admin AKS access via `azure/use-kubelogin@v1` and `azure/aks-set-context@v5`
6. Updates the Kubernetes deployment image and waits for rollout

Important branch note:

- Pushing to `dev` does not deploy unless the workflow is changed to include `dev`
- Merging `dev` into `main` creates a new push on `main`, which triggers a redeploy

## Commands You Will Reuse Often

Get tenant ID:

```bash
az account show --query tenantId -o tsv
```

Get subscription ID:

```bash
az account show --query id -o tsv
```

List app registrations:

```bash
az ad app list --query "[].{name:displayName,clientId:appId}" -o table
```

Get the client ID for this app:

```bash
az ad app list --display-name "fastapi-aks-github-actions" --query "[0].appId" -o tsv
```

List federated credentials on the app:

```bash
az ad app federated-credential list --id <AZURE_CLIENT_ID> -o json
```

Check AKS cluster ID:

```bash
az aks show --resource-group fastapi-rg --name fastapi-aks-cluster-dm --query id -o tsv
```

Check ACR ID:

```bash
az acr show --name fastapiacrdm --query id -o tsv
```

## Error 1: `azure/login@v2` failed because `AZURE_CREDENTIALS` was used

### Symptom

The older workflow used:

```yml
with:
  creds: ${{ secrets.AZURE_CREDENTIALS }}
```

### Cause

The workflow was using JSON credentials instead of GitHub OIDC with `client-id`, `tenant-id`, and `subscription-id`.

### Fix

Update the login step to:

```yml
- name: Login to Azure
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

Also add:

```yml
permissions:
  id-token: write
  contents: read
```

### Verification

In GitHub Actions logs, the Azure login step should complete before the Docker or AKS steps begin.

## Error 2: `AADSTS700213` no matching federated identity record found

### Symptom

GitHub Actions failed during Azure login with an error like:

```text
AADSTS700213: No matching federated identity record found for presented assertion subject ...
```

The exact subject seen on September 2, 2026 was:

```text
repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/main
```

### Cause

The federated credential in the Azure app registration did not exactly match the subject GitHub was sending.

This match must be exact, including:

- owner
- repo
- branch ref
- any numeric owner and repo suffixes included by GitHub in the subject

### Fix

List existing federated credentials:

```bash
az ad app federated-credential list --id <AZURE_CLIENT_ID> -o json
```

If the existing one is wrong, update it:

```bash
az ad app federated-credential update \
  --id <AZURE_CLIENT_ID> \
  --federated-credential-id github-main-fastapi-aks-basic-template \
  --parameters '{
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"],
    "description": "GitHub Actions OIDC for main branch"
  }'
```

If update does not work cleanly, delete and recreate:

```bash
az ad app federated-credential delete \
  --id <AZURE_CLIENT_ID> \
  --federated-credential-id github-main-fastapi-aks-basic-template
```

```bash
az ad app federated-credential create \
  --id <AZURE_CLIENT_ID> \
  --parameters '{
    "name": "github-main-fastapi-aks-basic-template",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Verification

Confirm the federated credential shows:

- issuer: `https://token.actions.githubusercontent.com`
- audience: `api://AzureADTokenExchange`
- subject exactly matching the GitHub Actions error

Then rerun the workflow.

## Error 3: `FederatedIdentityCredential ... already exists`

### Symptom

Azure CLI returned:

```text
FederatedIdentityCredential with name github-main-fastapi-aks-basic-template already exists.
```

### Cause

A federated credential with that name was already present, but its subject or issuer was wrong.

### Fix

Use `update` instead of `create`, or delete and recreate it.

Preferred:

```bash
az ad app federated-credential update \
  --id <AZURE_CLIENT_ID> \
  --federated-credential-id github-main-fastapi-aks-basic-template \
  --parameters '{
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

## Error 4: `az aks get-credentials --admin` authorization failed

### Symptom

GitHub Actions failed on:

```bash
az aks get-credentials --admin --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_AKS_CLUSTER
```

with an authorization error.

### Cause

The service principal used by GitHub Actions did not have the Azure role required for AKS admin kubeconfig access.

### Initial Fix Option

Grant the admin role:

```bash
az role assignment create \
  --assignee-object-id <SERVICE_PRINCIPAL_OBJECT_ID> \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster Admin Role" \
  --scope $(az aks show --resource-group fastapi-rg --name fastapi-aks-cluster-dm --query id -o tsv)
```

### Better Long-Term Fix

Do not use `--admin` in CI.

The workflow was updated to use:

- `azure/use-kubelogin@v1`
- `azure/aks-set-context@v5`
- `admin: "false"`

This is the preferred setup.

## Error 5: `listClusterUserCredential/action` authorization failed

### Symptom

After switching to non-admin access, GitHub Actions failed with:

```text
AuthorizationFailed ... does not have authorization to perform action
Microsoft.ContainerService/managedClusters/listClusterUserCredential/action
```

### Cause

The service principal did not have the Azure role needed for cluster user kubeconfig access.

### Fix

Grant the AKS cluster user role:

```bash
az role assignment create \
  --assignee-object-id f34fad83-a30e-403d-b0e0-7233443aaeda \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope $(az aks show --resource-group fastapi-rg --name fastapi-aks-cluster-dm --query id -o tsv)
```

Verify it:

```bash
az role assignment list \
  --assignee f34fad83-a30e-403d-b0e0-7233443aaeda \
  --scope $(az aks show --resource-group fastapi-rg --name fastapi-aks-cluster-dm --query id -o tsv) \
  -o table
```

### Important Note

Azure RBAC role assignments can take a few minutes to propagate.

If you grant access and immediately rerun the workflow, it can still fail once. Wait 1 to 5 minutes and retry.

## Error 6: ACR push or image-related permission issues

### Symptom

The workflow logs in to ACR, builds the image, then fails pushing the image.

### Cause

The GitHub Actions app registration is missing `AcrPush` on the ACR resource.

### Fix

Grant `AcrPush`:

```bash
az role assignment create \
  --assignee-object-id f34fad83-a30e-403d-b0e0-7233443aaeda \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush \
  --scope $(az acr show --name fastapiacrdm --query id -o tsv)
```

### Verification

Check that the workflow completes the `Push Docker Image to ACR` step.

## Error 7: AKS service deployed, but how do I find the URL?

### Symptom

The app was deployed, but the service endpoint was unknown.

### Cause

AKS created multiple public IPs in the managed node resource group, and only one of them was attached to the `LoadBalancer` service.

### Fix

The Kubernetes service manifest is:

```yaml
kind: Service
type: LoadBalancer
port: 80
targetPort: 8000
```

To inspect the public IPs:

```bash
az aks show --resource-group fastapi-rg --name fastapi-aks-cluster-dm --query "{name:name,nodeResourceGroup:nodeResourceGroup}" -o json
```

```bash
az network public-ip list --resource-group MC_fastapi-rg_fastapi-aks-cluster-dm_eastus -o table
```

```bash
az network lb list --resource-group MC_fastapi-rg_fastapi-aks-cluster-dm_eastus -o json
```

The public IP attached to the inbound load balancer rule for port `80` was:

```text
48.206.249.238
```

### Verification

```bash
curl http://48.206.249.238
```

## Error 8: `kubectl` from local machine could not reach the cluster

### Symptom

A local command failed with a DNS-related error when trying to connect to the AKS API server.

### Cause

The local environment did not have a working cluster context or could not resolve the AKS API server hostname at that moment.

### Fix

Refresh local credentials:

```bash
az login
az account set --subscription c9228dd2-1a35-4c93-a47c-60f9e28a7aec
az aks get-credentials --resource-group fastapi-rg --name fastapi-aks-cluster-dm --overwrite-existing
```

Then verify:

```bash
kubectl get nodes
kubectl get svc -A
```

## Error 9: Root endpoint needed to return current IST date and time

### Symptom

The `/` endpoint originally returned a static message only.

### Fix

The endpoint in [app/main.py](/Users/deepakmishra/work_2026/fastapi-base-test/app/main.py) was updated to return a single message string that includes the current IST date and time at request time.

Expected response shape:

```json
{
  "message": "Hello DEVOPS World! Current IST date and time: YYYY-MM-DD HH:MM:SS IST"
}
```

### Verification

After redeploy:

```bash
curl http://48.206.249.238/
```

## GitHub Secrets Checklist

Make sure these GitHub repository secrets exist:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

GitHub path:

```text
Repository -> Settings -> Secrets and variables -> Actions
```

## Required Azure Access Checklist

The GitHub Actions app should have:

- `AcrPush` on the ACR
- `Azure Kubernetes Service Cluster User Role` on the AKS cluster

Depending on your cluster and future workflow changes, you may also need Kubernetes RBAC inside the cluster, but today the Azure-side fixes were enough to get the deployment through.

## Fast Verification Checklist

Use this list when something breaks again:

1. Check GitHub secrets exist and are correct
2. Confirm workflow is running on the branch you pushed
3. Confirm the app registration client ID is the one used in GitHub
4. Check federated credential `issuer`, `audiences`, and exact `subject`
5. Confirm `AcrPush` is assigned on ACR
6. Confirm `Azure Kubernetes Service Cluster User Role` is assigned on AKS
7. Wait a few minutes after new role assignments
8. Rerun the workflow
9. If deployment succeeds, check the public service URL

## Useful Recovery Commands

Rerun a rollout manually:

```bash
kubectl rollout restart deployment/dmfastapi-app
kubectl rollout status deployment/dmfastapi-app
```

Check service exposure:

```bash
kubectl get svc
```

Check pods:

```bash
kubectl get pods
```

Check logs:

```bash
kubectl logs <pod-name>
```

## Final Notes

- The current workflow deploys only `main`
- Merging `dev` into `main` will trigger a redeploy
- If you later want a separate `dev` deployment, add `dev` to the workflow trigger and create a separate federated credential for the `dev` branch subject
