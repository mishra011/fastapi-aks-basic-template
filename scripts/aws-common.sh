#!/usr/bin/env bash
# Shared configuration; source from deployment/bootstrap scripts.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform/aws"
require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; return 1; }
  done
}
load_config() {
  # CI provides these explicitly; local commands fall back to AWS Terraform outputs.
  AWS_REGION="${AWS_REGION:-$(terraform -chdir="$TF_DIR" output -raw aws_region)}"
  EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-$(terraform -chdir="$TF_DIR" output -raw cluster_name)}"
  ECR_REPOSITORY_URL="${ECR_REPOSITORY_URL:-$(terraform -chdir="$TF_DIR" output -raw ecr_repository_url)}"
  KUBE_NAMESPACE="${KUBE_NAMESPACE:-$(terraform -chdir="$TF_DIR" output -raw namespace)}"
  HELM_RELEASE="${HELM_RELEASE:-fastapi-app}"
  export AWS_REGION EKS_CLUSTER_NAME ECR_REPOSITORY_URL KUBE_NAMESPACE HELM_RELEASE
}
set_context() {
  # Isolate kubeconfig so deployment never uses an unrelated current context.
  KUBECONFIG="$(mktemp)"
  export KUBECONFIG
  trap 'rm -f "$KUBECONFIG"' EXIT
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" --kubeconfig "$KUBECONFIG"
}
