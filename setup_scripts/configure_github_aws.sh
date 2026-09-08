#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/aws-common.sh"
require_tools terraform gh
load_config
repository="${GITHUB_REPOSITORY:-$(cd "$REPO_ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner)}"
role_arn="$(terraform -chdir="$TF_DIR" output -raw github_role_arn)"
gh variable set AWS_REGION --repo "$repository" --body "$AWS_REGION"
gh variable set EKS_CLUSTER_NAME --repo "$repository" --body "$EKS_CLUSTER_NAME"
gh variable set ECR_REPOSITORY_URL --repo "$repository" --body "$ECR_REPOSITORY_URL"
gh variable set KUBE_NAMESPACE --repo "$repository" --body "$KUBE_NAMESPACE"
gh variable set HELM_RELEASE --repo "$repository" --body "$HELM_RELEASE"
gh secret set AWS_ROLE_ARN --repo "$repository" --body "$role_arn"
echo "Configured AWS deployment variables and role ARN for $repository. Push the aws branch to deploy."
