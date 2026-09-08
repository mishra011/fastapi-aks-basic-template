#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aws-common.sh"
require_tools aws kubectl helm curl
load_config
: "${IMAGE_TAG:?Set IMAGE_TAG to an image already pushed to ECR, or run scripts/deploy.sh}"
set_context
helm lint "$REPO_ROOT/infrastructure/helm/fastapi"
# Namespace is created once by bootstrap, because CI has namespace-scoped access.
helm upgrade --install "$HELM_RELEASE" "$REPO_ROOT/infrastructure/helm/fastapi" \
  --namespace "$KUBE_NAMESPACE" \
  --set-string image.repository="$ECR_REPOSITORY_URL" \
  --set-string image.tag="$IMAGE_TAG" \
  --wait --timeout 15m
kubectl get pods,services --namespace "$KUBE_NAMESPACE"
# EKS Services expose a DNS hostname; wait for provisioning and target health.
for attempt in $(seq 1 60); do
  hostname="$(kubectl get service --namespace "$KUBE_NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')"
  if [[ -n "$hostname" ]] && curl --fail --silent --show-error --connect-timeout 5 --max-time 10 "http://$hostname/health"; then
    printf '\nApplication URL: http://%s\n' "$hostname"
    exit 0
  fi
  sleep 10
done
echo "Timed out waiting for the public load balancer health endpoint." >&2
exit 1
