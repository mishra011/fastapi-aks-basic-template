#!/usr/bin/env bash
set -euo pipefail

az aks get-credentials --admin --name fastapi-aks-cluster-dm --resource-group fastapi-rg
kubectl get nodes

helm upgrade --install fastapi-app ./infrastructure/helm/fastapi
