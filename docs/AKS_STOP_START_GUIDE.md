# AKS Stop and Restart Guide

This guide explains how to stop and restart the AKS cluster used by this project to help reduce Azure costs when the app is not needed.

## Cluster Details

This repository currently uses:

```text
Resource group: fastapi-rg
AKS cluster: fastapi-aks-cluster-dm
```

## Why Stop the Cluster

Stopping the AKS cluster helps reduce cost because the Kubernetes control plane and worker nodes stop running.

This usually saves a meaningful amount of money, but it does not reduce total Azure cost to zero. Some resources can still incur charges, including:

- public IP addresses
- load balancer resources
- managed disks
- Azure Container Registry
- monitoring resources such as Log Analytics

## Stop the Cluster

Run:

```bash
az aks stop --name fastapi-aks-cluster-dm --resource-group fastapi-rg
```

If you want the command to return immediately without waiting:

```bash
az aks stop --name fastapi-aks-cluster-dm --resource-group fastapi-rg --no-wait
```

## Verify the Cluster Is Stopped

Run:

```bash
az aks show --name fastapi-aks-cluster-dm --resource-group fastapi-rg --query powerState.code -o tsv
```

Expected result:

```text
Stopped
```

If you see `Stopping`, wait a little and run the check again.

## Start the Cluster Again

Run:

```bash
az aks start --name fastapi-aks-cluster-dm --resource-group fastapi-rg
```

If you want the command to return immediately without waiting:

```bash
az aks start --name fastapi-aks-cluster-dm --resource-group fastapi-rg --no-wait
```

## Verify the Cluster Is Running

Run:

```bash
az aks show --name fastapi-aks-cluster-dm --resource-group fastapi-rg --query powerState.code -o tsv
```

Expected result:

```text
Running
```

After the cluster is back up, refresh local Kubernetes credentials if needed:

```bash
az aks get-credentials --resource-group fastapi-rg --name fastapi-aks-cluster-dm --overwrite-existing
```

Then verify Kubernetes access:

```bash
kubectl get nodes
kubectl get pods
kubectl get svc
```

## Check the App After Restart

The app was previously reachable at:

```text
http://48.206.249.238
```

After the cluster starts, test the endpoint:

```bash
curl http://48.206.249.238/
```

If the response fails right after startup, wait a minute for the nodes, pods, and load balancer to become ready, then try again.

## Common Notes

- Stopping the cluster will make the app unavailable until the cluster is started again.
- If GitHub Actions deploys while the cluster is stopped, the deployment job may fail.
- After restart, pods may take some time to become healthy.
- If the public IP changes in the future, check the service again with `kubectl get svc`.
