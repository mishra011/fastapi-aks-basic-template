#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aws-common.sh"
require_tools aws docker git
load_config
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$REPO_ROOT" rev-parse HEAD)-local-$(date -u +%Y%m%d%H%M%S)}"
export IMAGE_TAG
registry="${ECR_REPOSITORY_URL%%/*}"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
docker buildx build --platform linux/amd64 --tag "$ECR_REPOSITORY_URL:$IMAGE_TAG" --push "$REPO_ROOT"
exec "$REPO_ROOT/scripts/deploy-helm.sh"
