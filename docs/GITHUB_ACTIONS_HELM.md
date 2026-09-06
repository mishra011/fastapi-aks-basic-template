# Deploy FastAPI on pushes to dev

The workflow in `.github/workflows/deploy.yml` builds an image tagged with the
commit SHA, pushes it to ACR, and installs or upgrades the Helm release. Terraform
continues to manage AKS and ACR. Existing raw Kubernetes manifests remain usable.

Run the following sections in order in the same terminal. These are one-time
configuration commands followed by a first push. AKS and ACR must already exist
and AKS must be running. Your Azure account needs permission to create an app and
service principal and assign roles on AKS and ACR. Your GitHub account needs
permission to manage repository Actions secrets and variables.

## 1. Install and authenticate the GitHub CLI

`gh` was not available in the inspected terminal. On macOS:

```bash
brew install gh
gh auth login --hostname github.com --git-protocol https --web
az login
cd /Users/deepakmishra/work_2026/fastapi-base-test

REPO="mishra011/fastapi-aks-basic-template"
az account set --subscription c9228dd2-1a35-4c93-a47c-60f9e28a7aec
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
AKS_ID=$(az aks show -g fastapi-rg -n fastapi-aks-cluster-dm --query id -o tsv)
ACR_ID=$(az acr show -g fastapi-rg -n fastapiacrdm --query id -o tsv)
gh repo view "$REPO"
```

## 2. Create a dedicated GitHub dev deployment identity

Run this creation block once. It creates an application and service principal,
without a client password. This guide replaces the repository's existing Azure
identity secrets with this dedicated identity. If you already have an identity
you want to retain, set `CLIENT_ID` to its application/client ID instead of running
the app-create command, then use `az ad sp show --id "$CLIENT_ID" --query id -o tsv`
to obtain `SP_OBJECT_ID` instead of creating a service principal.

```bash
CLIENT_ID=$(az ad app create \
  --display-name fastapi-github-dev-deploy \
  --query appId -o tsv)
SP_OBJECT_ID=$(az ad sp create --id "$CLIENT_ID" --query id -o tsv)
```

If service-principal creation reports that the new application cannot be found,
wait briefly and retry only the `az ad sp create` command.

## 3. Trust pushes from dev using OIDC

Inspect the current GitHub OIDC configuration and existing Azure trust entries:

```bash
gh api "repos/$REPO/actions/oidc/customization/sub"
az ad app federated-credential list --id "$CLIENT_ID" -o table
```

This repository previously emitted GitHub's immutable subject format, which
includes numeric owner and repository IDs. Obtain current IDs rather than copying
old values. The block below assumes the default branch-based subject template;
if the inspection shows custom `include_claim_keys`, reconcile that template first.
Do not add a GitHub job `environment:` to this workflow: it changes the subject
from a branch subject to an environment subject.

```bash
OWNER_LOGIN=$(gh api "repos/$REPO" --jq '.owner.login')
OWNER_ID=$(gh api "repos/$REPO" --jq '.owner.id')
REPO_NAME=$(gh api "repos/$REPO" --jq '.name')
REPO_ID=$(gh api "repos/$REPO" --jq '.id')
OIDC_SUBJECT="repo:${OWNER_LOGIN}@${OWNER_ID}/${REPO_NAME}@${REPO_ID}:ref:refs/heads/dev"

az ad app federated-credential create --id "$CLIENT_ID" --parameters "{
  \"name\": \"github-dev\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"$OIDC_SUBJECT\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"
```

If reusing an identity with a `github-dev` credential, inspect it and use
`az ad app federated-credential update --id "$CLIENT_ID" --federated-credential-id github-dev --parameters ...`
with the same JSON instead of creating a duplicate. Preserve other branch credentials.

## 4. Grant deployment permissions

```bash
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush --scope "$ACR_ID"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" --scope "$AKS_ID"
```

The live AKS settings inspected on September 6, 2026 had `aadProfile: null` and
local accounts enabled, matching the current Terraform configuration. On this
non-Entra cluster, retrieving cluster-user credentials provides broad cluster
access. These commands do not establish namespace-limited authorization. If you
later enable Entra integration, Kubernetes authorization must also be configured;
the Cluster User role alone will not grant deployment access. Terraform already
assigns `AcrPull` to the AKS kubelet identity.

Allow a few minutes for new Azure role assignments and OIDC trust to propagate.

## 5. Add repository secrets and variables from the CLI

These commands create or replace repository-level values. No Azure client secret,
`AZURE_CREDENTIALS` JSON, registry password, or stored kubeconfig is required.

```bash
gh secret set AZURE_CLIENT_ID --repo "$REPO" --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID --repo "$REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUBSCRIPTION_ID"

gh variable set AZURE_RESOURCE_GROUP --repo "$REPO" --body fastapi-rg
gh variable set AZURE_AKS_CLUSTER --repo "$REPO" --body fastapi-aks-cluster-dm
gh variable set ACR_NAME --repo "$REPO" --body fastapiacrdm
gh variable set IMAGE_NAME --repo "$REPO" --body dmfastapi-app
gh variable set HELM_RELEASE --repo "$REPO" --body fastapi-app
gh variable set KUBE_NAMESPACE --repo "$REPO" --body fastapi-helm

gh secret list --repo "$REPO"
gh variable list --repo "$REPO"
```

This targets the same namespace and release as the manual Helm instructions. If
you instead installed using `scripts/deploy-helm.sh`, that script used your current
namespace (usually `default`); set `KUBE_NAMESPACE` to that namespace to update
that release, or use `fastapi-helm` to create a separate deployment.

## 6. Commit and push to dev

Check branches before selecting the appropriate switch command:

```bash
git fetch origin
git branch --all
```

If a local `dev` branch exists, run `git switch dev`. If only `origin/dev` exists,
run `git switch --track origin/dev`. If neither exists, run `git switch -c dev`.
Do not force a switch if Git reports conflicting local changes.

Then review and commit the workflow and chart:

```bash
helm lint ./infrastructure/helm/fastapi
git diff -- .github/workflows/deploy.yml
git add .github/workflows/deploy.yml infrastructure/helm/fastapi docs/GITHUB_ACTIONS_HELM.md
git diff --cached --stat
git commit -m "Deploy FastAPI with Helm on dev pushes"
git push -u origin dev
```

The workflow and chart must be present on `dev`. Pushes to `main` no longer trigger
this workflow. Repository rules and organization Actions policies still apply.

## 7. Watch the run and inspect FastAPI

```bash
gh run list --repo "$REPO" --workflow deploy.yml --branch dev --limit 5
```

Copy the new run ID from that list into this command:

```bash
gh run watch RUN_ID --repo "$REPO" --exit-status
```

Once it succeeds:

```bash
az aks get-credentials -g fastapi-rg -n fastapi-aks-cluster-dm --overwrite-existing
helm list -n fastapi-helm
kubectl get pods,services -n fastapi-helm
```

Open `http://<EXTERNAL-IP>/docs` using the `fastapi-app` service IP.
If you chose another namespace, substitute it in these commands.

For a failed run:

```bash
gh run view RUN_ID --repo "$REPO" --log-failed
```

For `AADSTS700213`, compare the exact subject in the error with the Azure
federated credential. Names, IDs, branch, issuer, and audience must match.
For image-pull failures, inspect pod events with `kubectl describe pod` and verify
the Terraform-managed kubelet `AcrPull` assignment. Each subsequent push to `dev`
builds a SHA-tagged image and upgrades the release automatically.

## References

- [GitHub immutable OIDC subjects](https://docs.github.com/en/actions/reference/security/oidc)
- [GitHub CLI secrets](https://cli.github.com/manual/gh_secret_set)
- [GitHub CLI variables](https://cli.github.com/manual/gh_variable_set)
- [AKS kubeconfig access and roles](https://learn.microsoft.com/en-us/azure/aks/control-kubeconfig-access)
- [Helm setup action](https://github.com/Azure/setup-helm)
