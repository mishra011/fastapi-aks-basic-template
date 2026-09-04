#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"
RESOURCE_GROUP="fastapi-rg"
AKS_CLUSTER="fastapi-aks-cluster-dm"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed or not on PATH."
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  echo "Error: Azure CLI is not installed or not on PATH."
  exit 1
fi

if [[ ! -d "${TF_DIR}" ]]; then
  echo "Error: Terraform directory not found at ${TF_DIR}."
  exit 1
fi

if [[ ! -f "${TF_DIR}/main.tf" ]]; then
  echo "Error: ${TF_DIR}/main.tf not found."
  exit 1
fi

cd "${TF_DIR}"

NODE_RESOURCE_GROUP="$(az aks show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --query nodeResourceGroup \
  -o tsv 2>/dev/null || true)"

echo "This will destroy the Terraform-managed Azure resources for this project."
echo "Terraform directory: ${TF_DIR}"
echo "Resources expected from current config:"
echo "  - Resource Group: ${RESOURCE_GROUP}"
echo "  - AKS Cluster: ${AKS_CLUSTER}"
echo "  - ACR: fastapiacrdm"
if [[ -n "${NODE_RESOURCE_GROUP}" ]]; then
  echo "  - AKS managed Resource Group: ${NODE_RESOURCE_GROUP}"
fi
echo

read -r -p "Type DESTROY to continue: " confirm

if [[ "${confirm}" != "DESTROY" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Checking Azure login context..."
az account show >/dev/null

echo "Initializing Terraform..."
terraform init -input=false

echo "Destroying Terraform-managed infrastructure..."
terraform destroy -auto-approve

echo "Verifying Azure resource groups were removed..."

main_rg_exists="$(az group exists --name "${RESOURCE_GROUP}")"

if [[ "${main_rg_exists}" != "false" ]]; then
  echo "Warning: Resource group ${RESOURCE_GROUP} still exists."
  exit 1
fi

if [[ -n "${NODE_RESOURCE_GROUP}" ]]; then
  node_rg_exists="$(az group exists --name "${NODE_RESOURCE_GROUP}")"
  if [[ "${node_rg_exists}" != "false" ]]; then
    echo "Warning: AKS managed resource group ${NODE_RESOURCE_GROUP} still exists."
    exit 1
  fi
fi

echo "Cleanup complete. Azure resource groups were removed successfully."
