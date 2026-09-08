#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/aws-common.sh"
require_tools terraform aws kubectl helm
load_config
aws sts get-caller-identity
echo "This removes the Helm release and AWS infrastructure for $EKS_CLUSTER_NAME in $AWS_REGION."
echo "ECR containing images is protected unless ecr_force_delete=true is explicitly applied first."
read -r -p "Type DESTROY to continue: " confirm
[[ "$confirm" == DESTROY ]] || { echo "Aborted."; exit 1; }
set_context
# Delete Kubernetes-managed load balancers before removing their controller/cluster.
helm uninstall "$HELM_RELEASE" --namespace "$KUBE_NAMESPACE" --ignore-not-found --wait --timeout 15m
# Also remove the optional raw-manifest demo Service if it was deployed.
kubectl delete service fastapi-service --namespace "$KUBE_NAMESPACE" --ignore-not-found --wait=true --timeout=15m
remaining="$(kubectl get services --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')"
[[ -z "$remaining" ]] || { printf 'Remove these LoadBalancer Services before destroying:\n%s\n' "$remaining"; exit 1; }
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" destroy
remaining_state="$(terraform -chdir="$TF_DIR" state list)"
[[ -z "$remaining_state" ]] || { echo "Terraform state still contains resources; inspect before retrying."; exit 1; }
echo "AWS Terraform state is empty after destroy. Azure state was not touched."
