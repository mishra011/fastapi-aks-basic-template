#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/aws-common.sh"
require_tools aws terraform kubectl
aws sts get-caller-identity
terraform -chdir="$TF_DIR" init -input=false
# Terraform displays its plan and asks for approval before creating billable resources.
terraform -chdir="$TF_DIR" apply
load_config
set_context
kubectl create namespace "$KUBE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "AWS infrastructure and application namespace are ready."
terraform -chdir="$TF_DIR" output
