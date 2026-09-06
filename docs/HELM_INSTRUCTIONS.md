# Helm deployment guide: local CLI and GitHub Actions

This guide collects the deployment commands and troubleshooting from this
project's Helm setup. Run the numbered setup sections in order, in the same
terminal, and stop if a command fails. Sections marked optional are alternatives,
not extra steps to run on every deployment. Cloud configuration and deployment
commands change real resources; reading this guide does not execute them.

## Contents

- [1. Deployment options and project configuration](#1-deployment-options-and-project-configuration)
- [2. Tools, login, and shell variables](#2-tools-login-and-shell-variables)
- [3. Provision or reuse Terraform infrastructure](#3-provision-or-reuse-terraform-infrastructure)
- [4. Deploy manually with Helm](#4-deploy-manually-with-helm)
- [5. Create or retrieve the Azure deployment identity](#5-create-or-retrieve-the-azure-deployment-identity)
- [6. Configure GitHub OIDC trust](#6-configure-github-oidc-trust)
- [7. Grant Azure permissions](#7-grant-azure-permissions)
- [8. Set GitHub secrets and variables](#8-set-github-secrets-and-variables)
- [9. Understand the GitHub Actions workflow](#9-understand-the-github-actions-workflow)
- [10. Push to dev and monitor deployment](#10-push-to-dev-and-monitor-deployment)
- [11. Troubleshooting](#11-troubleshooting)
- [12. Switch deployment methods and clean up](#12-switch-deployment-methods-and-clean-up)
- [13. Permission reference](#13-permission-reference)
- [14. Official references](#14-official-references)

## 1. Deployment options and project configuration

Terraform creates Azure infrastructure. Helm renders Kubernetes templates and
manages the application as a named release. Neither replaces the other here.

| Option | Infrastructure | FastAPI deployment | Status in this repository |
| --- | --- | --- | --- |
| Original manual method | Terraform | `kubectl apply` with raw YAML | Retained |
| Manual Helm | Same Terraform | Local `helm upgrade --install` | Available |
| Automated Helm | Same Terraform | GitHub Actions on pushes to `dev` | Configured workflow; requires cloud setup below |
| Terraform-managed Helm | Terraform | Terraform Helm provider and `helm_release` | Possible, but not implemented here |

Do not manage the same Helm release with both Terraform and standalone Helm
without a deliberate ownership migration. For this learning project, keep
Terraform responsible for AKS/ACR and choose raw YAML or Helm for the app.

| Setting | Value |
| --- | --- |
| Repository | `mishra011/fastapi-aks-basic-template` |
| Local directory | `/Users/deepakmishra/work_2026/fastapi-base-test` |
| Deployment branch | `dev` |
| Subscription configured in Terraform | `c9228dd2-1a35-4c93-a47c-60f9e28a7aec` |
| Resource group | `fastapi-rg` |
| AKS cluster | `fastapi-aks-cluster-dm` |
| ACR name / login server | `fastapiacrdm` / `fastapiacrdm.azurecr.io` |
| Container image | `dmfastapi-app` |
| Chart directory | `infrastructure/helm/fastapi` |
| Helm release / recommended namespace | `fastapi-app` / `fastapi-helm` |
| Raw YAML Deployment / Service | `dmfastapi-app` / `fastapi-service` |

The chart's `Chart.yaml` describes the chart; `values.yaml` contains configurable
defaults; `templates/` produces Deployment and Service YAML. The defaults are two
replicas, image tag `latest`, container port 8000, and a LoadBalancer Service on
port 80. Manual commands below override the tag with a timestamp; CI uses the
commit SHA. A new tag changes the pod template and triggers a rollout.

## 2. Tools, login, and shell variables

On macOS, install any missing CLI tools with Homebrew:

```bash
brew install helm gh azure-cli kubectl
helm version --short
gh --version
az version
kubectl version --client
docker version
docker buildx version
```

Homebrew installs the clients. Version commands verify they can run. Install and
start Docker Desktop separately if Docker is unavailable; `docker version` should
show a working server. These checks do not contact or deploy to Kubernetes.

```bash
cd /Users/deepakmishra/work_2026/fastapi-base-test
gh auth login --hostname github.com --git-protocol https --web
az login
az account set --subscription c9228dd2-1a35-4c93-a47c-60f9e28a7aec

REPO="mishra011/fastapi-aks-basic-template"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

az account show --query '{name:name,id:id,tenantId:tenantId,state:state}' -o table
gh repo view "$REPO"
```

`cd` makes relative paths resolve from the project root. `gh auth login` signs your
local CLI into GitHub; it does not configure Azure access for Actions. `az login`
signs in your human Azure account. `az account set` selects the subscription for
subsequent commands; verify it before provisioning or assigning permissions.
`gh repo view` checks that you are targeting the intended repository.

`$(...)` captures command output in a shell variable. `--query` selects a field
using JMESPath; `-o tsv` returns plain text without JSON quotes. Variables disappear
when you close the terminal. Recover them by rerunning read commands, not by
recreating the app identity. A trailing `\` continues a command on the next line;
do not put spaces after it.

## 3. Provision or reuse Terraform infrastructure

Skip provisioning if this project's AKS and ACR already exist and are running.
Terraform must also be installed if you use these commands.

```bash
terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform plan
terraform -chdir=infrastructure/terraform apply
```

`-chdir` runs Terraform in its configuration directory. `init` installs providers
and initializes the backend; `plan` previews changes; `apply` asks for confirmation
and performs them. The current configuration creates the resource group, ACR,
AKS, and the kubelet's `AcrPull` assignment. Your human identity needs Azure
resource-creation permissions and role-assignment permission for that last step.
Keep the existing Terraform state; do not commit state files or recreate existing
resources from an unrelated empty state.

Read the resource IDs after provisioning, or when resuming setup:

```bash
AKS_ID=$(az aks show -g fastapi-rg -n fastapi-aks-cluster-dm --query id -o tsv)
ACR_ID=$(az acr show -g fastapi-rg -n fastapiacrdm --query id -o tsv)
az aks show -g fastapi-rg -n fastapi-aks-cluster-dm \
  --query '{power:powerState.code,aad:aadProfile,disableLocalAccounts:disableLocalAccounts}' -o json
```

The IDs are full Azure resource paths used to limit role-assignment scope. The
last command checks cluster power and authentication settings. The cluster was
observed on September 6, 2026 with `aadProfile: null` and local accounts enabled;
recheck because live settings can change. If it is stopped, follow the separate
[AKS stop/start guide](AKS_STOP_START_GUIDE.md) before deployment.

## 4. Deploy manually with Helm

### Connect to AKS

```bash
az aks get-credentials \
  --resource-group fastapi-rg \
  --name fastapi-aks-cluster-dm \
  --overwrite-existing
kubectl config current-context
kubectl get nodes
```

`get-credentials` downloads cluster-user credentials into your local kubeconfig
and selects the cluster context. `--overwrite-existing` refreshes its existing
entry. Check the context to avoid deploying to another cluster. `get nodes`
verifies connectivity and permission to list nodes. The Azure Cluster User role
allows credential retrieval; Kubernetes authorization determines API access.
See section 13 for the non-Entra cluster caveat.

### Build an AKS-compatible image and push it

```bash
az acr login --name fastapiacrdm
IMAGE_TAG="helm-$(date +%Y%m%d%H%M%S)"
docker buildx build --platform linux/amd64 \
  -t "fastapiacrdm.azurecr.io/dmfastapi-app:$IMAGE_TAG" \
  --push .
```

`az acr login` authenticates Docker to the registry using your Azure session.
Your human identity needs registry push access, such as `AcrPush` for this
registry's role mode. The timestamp gives this build a distinct tag.
`buildx build` builds the root Dockerfile; `.` is the build context; `-t` names the
image; `--push` uploads it. `--platform linux/amd64` targets the configured AKS
nodes even when building on an Apple Silicon Mac. AKS uses its own kubelet
identity, not your Docker login, to pull the resulting image.

### Validate without deploying

```bash
helm lint ./infrastructure/helm/fastapi
helm template fastapi-app ./infrastructure/helm/fastapi \
  --namespace fastapi-helm --set-string image.tag="$IMAGE_TAG"
```

`lint` checks chart structure and common mistakes. `template` prints rendered
Kubernetes YAML for inspection. Neither creates cluster resources or proves the
image will start successfully. Helm lint and rendering passed during this setup.

### Install or upgrade the app

```bash
helm upgrade --install fastapi-app ./infrastructure/helm/fastapi \
  --namespace fastapi-helm \
  --create-namespace \
  --set-string image.tag="$IMAGE_TAG" \
  --wait --timeout 10m
```

| Argument | What it does and why |
| --- | --- |
| `upgrade --install` | Upgrades an existing release or installs it on the first run. |
| `fastapi-app` | Stable release name used for history, status, and uninstall. |
| Chart path | Uses this repository's local templates; no Helm repository registration is needed. |
| `--namespace fastapi-helm` | Keeps the Helm app separate from the original YAML deployment. |
| `--create-namespace` | Creates the namespace on installation if missing; requires namespace-creation permission. |
| `--set-string image.tag=...` | Overrides the default `latest` tag and preserves the value as a string. |
| `--wait --timeout 10m` | Waits up to ten minutes for supported readiness checks. It does not run an application-level test or automatically roll back on failure. |

Helm needs Kubernetes access to manage Deployments, Services, and its release
metadata Secrets in the namespace, plus discovery/read/watch access. Custom
namespace-restricted RBAC would normally use a pre-created namespace and omit
`--create-namespace`. The current cluster authentication mode is broader.

Other overrides discussed in the chat can be applied on the same release:

```bash
helm upgrade --install fastapi-app ./infrastructure/helm/fastapi \
  --namespace fastapi-helm --create-namespace \
  --set-string image.tag="$IMAGE_TAG" \
  --set replicaCount=2 --set service.type=LoadBalancer \
  --wait --timeout 10m
```

Use this as an alternative deployment command when adjusting values. Supplying
the image tag again avoids unintentionally returning to the chart's `latest`
default. Persistent defaults can be edited in `values.yaml`; CI tag overrides win.

### Verify the release and open FastAPI

```bash
helm list -n fastapi-helm
helm status fastapi-app -n fastapi-helm
kubectl get pods -n fastapi-helm
kubectl get svc fastapi-app -n fastapi-helm --watch
```

`helm list` lists releases; `status` shows release details. `get pods` shows pod
health. `get svc --watch` streams changes until you press Ctrl+C. Once
`EXTERNAL-IP` is populated, open `http://<EXTERNAL-IP>/docs` in your browser.
The public Service forwards port 80 to FastAPI on container port 8000.

### Existing convenience scripts

```bash
./scripts/deploy-helm.sh
```

This existing script gets AKS credentials with `--admin`, lists nodes, and runs
Helm without an explicit namespace or image-tag override. It requires admin
credential-retrieval permission, uses the current namespace (usually `default`),
and does not build/push the image. It is not equivalent to the recommended
`fastapi-helm` commands above. Prefer the explicit commands for consistency with
CI. To locate an earlier script-created release, run `helm list --all-namespaces`.

## 5. Create or retrieve the Azure deployment identity

GitHub requires its own Azure identity. Your local `az login` is not inherited by
the runner. An app registration defines the application; its service principal
is the tenant-local identity that receives Azure roles.

### Option A: Create a new identity once

```bash
CLIENT_ID=$(az ad app create \
  --display-name fastapi-github-dev-deploy \
  --query appId -o tsv)

SP_OBJECT_ID=$(az ad sp create \
  --id "$CLIENT_ID" \
  --query id -o tsv)
```

The first command creates an Entra application and stores its `appId` in
`CLIENT_ID`. The second creates its service principal and stores the principal's
object `id` in `SP_OBJECT_ID`. Neither command creates a client password. Creation
needs the tenant's permitted app/service-principal creation rights; subscription
ownership alone does not necessarily grant Entra application-management rights.

Run each creation command only once. If the new app has not propagated, retry
only service-principal creation after a short wait. If the service principal
already exists, use `az ad sp show` below instead. Repeated `app create` commands
can create different apps with the same display name.

### Option B: Retrieve an existing CLIENT_ID

When resuming setup in a new terminal, first list matching applications:

```bash
az ad app list --display-name fastapi-github-dev-deploy \
  --query '[].{Name:displayName,ClientId:appId,ApplicationObjectId:id}' -o table
```

Choose the intended application from the results, then set its client ID:

```bash
CLIENT_ID="PASTE_THE_APPLICATION_CLIENT_ID"
SP_OBJECT_ID=$(az ad sp show --id "$CLIENT_ID" --query id -o tsv)
az ad app show --id "$CLIENT_ID" \
  --query '{name:displayName,clientId:appId}' -o table
```

If your app uses a different display name, substitute that name in the list
command. Do not blindly select the first match when duplicates exist. GitHub
does not reveal an existing secret value through `gh secret list`; retrieve the
ID from Azure and deliberately align GitHub with the chosen identity.

| Identifier | Purpose |
| --- | --- |
| `CLIENT_ID` (`appId`) | Passed to `azure/login` and stored as `AZURE_CLIENT_ID`. |
| `SP_OBJECT_ID` (service principal `id`) | Recipient of Azure role assignments. |
| Application object ID | Directory ID of the app registration; different from both IDs above. |
| `TENANT_ID` | Entra directory in which the deployment identity authenticates. |
| `SUBSCRIPTION_ID` | Subscription containing AKS and ACR. |

## 6. Configure GitHub OIDC trust

OIDC lets GitHub exchange a short-lived token for Azure access without a stored
Azure client password. Trust answers "which workflow may use this identity?";
roles in section 7 answer "what may that identity do?" Both are required.

First inspect existing settings:

```bash
gh api "repos/$REPO/actions/oidc/customization/sub"
az ad app federated-credential list --id "$CLIENT_ID" \
  --query '[].{name:name,subject:subject,issuer:issuer,audiences:audiences}' -o json
```

These commands read the repository's OIDC configuration and the application's
trust entries. Preserve existing credentials for other branches. This project
emitted the following exact immutable subject in its login error:

```text
repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/dev
```

Both numeric IDs are part of the subject. For this repository, define:

```bash
DEV_TRUST='{
  "name": "github-dev",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/dev",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

If `github-dev` does not exist and no other entry already matches this trust:

```bash
az ad app federated-credential create \
  --id "$CLIENT_ID" --parameters "$DEV_TRUST"
```

If `github-dev` already exists but needs correction, update it instead:

```bash
az ad app federated-credential update \
  --id "$CLIENT_ID" \
  --federated-credential-id github-dev \
  --parameters "$DEV_TRUST"
```

Choose create OR update, not both. If matching trust already exists under another
name, do not create a duplicate; verify the identity selected in GitHub. These
operations require application-management rights, such as appropriate app
ownership or an Entra administrative role permitted by your tenant policy.

| Trust field | Meaning |
| --- | --- |
| `name` | Azure entry name used to manage the credential; not a token claim. |
| `issuer` | GitHub's token issuer, including exact spelling and slash handling. |
| `subject` | Exact repository identity and `dev` branch authorized to use the app. |
| `audiences` | Expected token-exchange audience used by Azure Login. |

For a renamed or different repository, retrieve current names and IDs:

```bash
OWNER_LOGIN=$(gh api "repos/$REPO" --jq '.owner.login')
OWNER_ID=$(gh api "repos/$REPO" --jq '.owner.id')
REPO_NAME=$(gh api "repos/$REPO" --jq '.name')
REPO_ID=$(gh api "repos/$REPO" --jq '.id')
OIDC_SUBJECT="repo:${OWNER_LOGIN}@${OWNER_ID}/${REPO_NAME}@${REPO_ID}:ref:refs/heads/dev"
printf '%s\n' "$OIDC_SUBJECT"
```

`gh api` reads GitHub metadata; `--jq` extracts fields. This constructs the
immutable default branch subject, not arbitrary custom subject templates. Compare
against the actual token/error and rebuild `DEV_TRUST` if necessary. An older
repository may use a subject without IDs. Adding a job `environment:` changes the
subject to an environment-based one; repository variables do not do that.

## 7. Grant Azure permissions

Run these as your human administrator, with the identity and resource IDs from
earlier sections. Inspect current assignments first:

```bash
az role assignment list --assignee "$SP_OBJECT_ID" --all \
  --query '[].{Role:roleDefinitionName,Scope:scope}' -o table
```

Add the following assignments if missing:

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

`--assignee-object-id` specifies the service principal, not the application client
ID. `--assignee-principal-type` identifies its type explicitly.
`--scope` limits each assignment to the registry or cluster, rather than granting
Contributor across the entire subscription. `AcrPush` permits image push/pull for
this registry's current role mode. Cluster User permits retrieving the user
kubeconfig needed by `aks-set-context`.

The account executing role creation needs `Microsoft.Authorization/roleAssignments/write`
at the scope or a parent scope, for example through Owner or Role Based Access
Control Administrator, subject to any assignment conditions. Contributor alone
does not grant role-assignment rights. Allow a few minutes for propagation.

On this project's observed non-Entra cluster, cluster-user credentials provide
broad Kubernetes access. This is not namespace isolation. If you enable Entra
integration later, configure Kubernetes RBAC or Azure RBAC for Kubernetes as
well; Cluster User alone only grants credential retrieval.

Terraform already grants the AKS kubelet identity `AcrPull` on ACR. It needs pull
access to start containers, while GitHub needs push access to publish them. Do not
assign the workflow's roles to the kubelet or vice versa.

## 8. Set GitHub secrets and variables

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

`set` creates or replaces a repository value; `--repo` prevents configuring the
wrong repository; `--body` supplies the value. The identity IDs are not passwords,
but this workflow deliberately reads them through `secrets`. GitHub encrypts
secret values; listing secrets shows names and metadata, not their contents.
Variables hold non-secret deployment configuration and are read through `vars`.
Setting a secret with a variable's name does not satisfy a `vars` reference.

Your GitHub identity/token needs permission to manage Actions secrets and
variables for the repository. Use repository-level values here, not GitHub
environment-level values: the current job does not select an environment.
No `AZURE_CREDENTIALS` JSON, Azure client password, ACR password, or stored
kubeconfig is needed. Updating `AZURE_CLIENT_ID` must select the same application
that has both the federated credential and the role assignments.

The release and namespace match section 4. If you previously installed into
`default` using the script, either set `KUBE_NAMESPACE` to `default` to update that
release or deliberately deploy a separate release in `fastapi-helm`.

## 9. Understand the GitHub Actions workflow

The actual workflow is [deploy.yml](../.github/workflows/deploy.yml). Its relevant
configuration is:

```yaml
on:
  push:
    branches:
      - dev

permissions:
  id-token: write
  contents: read
```

`push.branches` triggers deployment when commits reach `dev`, including merges.
It does not deploy pushes to `main`. `contents: read` permits checkout of the
repository. `id-token: write` permits requesting a GitHub OIDC token; it does not
grant Azure access by itself. Azure trust and role assignments grant that access.

The login step reads the three secrets:

```yaml
- name: Login to Azure
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

| Workflow step/configuration | What it does and why |
| --- | --- |
| Checkout | Downloads the commit's code, Dockerfile, and Helm chart. |
| Variable validation | Fails early with a clear missing-variable message. |
| `azure/setup-helm@v5`, Helm `v4.2.4` | Installs the pinned Helm version used by this workflow. |
| Helm lint | Checks chart structure before building/deploying. |
| Azure Login | Exchanges the GitHub OIDC token for the selected Azure identity. |
| `azure/use-kubelogin@v1` | Installs the AKS Entra authentication helper; useful for Entra-enabled clusters. |
| `az acr login` | Authenticates the runner's Docker client to ACR. |
| Docker build/push | Publishes `ACR_NAME.azurecr.io/IMAGE_NAME:github.sha`; distinct commits have distinct tags. |
| `azure/aks-set-context@v5` | Gets cluster-user credentials with `admin: false` and kubelogin support. |
| Helm upgrade/install | Deploys the chart with the new image into `KUBE_NAMESPACE`. |
| Status commands | Prints release, pod, and Service information in the run log. |
| Concurrency group | Prevents overlapping deploy jobs in this group; running jobs are not canceled. Pending pushes can be coalesced. |
| Job timeout | Bounds the full build/deploy job to 25 minutes; Helm waits at most 10 minutes. |

The runner executes this deployment command using workflow environment variables:

```bash
helm upgrade --install "$HELM_RELEASE" ./infrastructure/helm/fastapi \
  --namespace "$KUBE_NAMESPACE" \
  --create-namespace \
  --set-string image.repository="$ACR_NAME.azurecr.io/$IMAGE_NAME" \
  --set-string image.tag="$IMAGE_TAG" \
  --wait --timeout 10m
```

In CI, `IMAGE_TAG` is `${{ github.sha }}`. These environment variables are populated
by the workflow; GitHub repository variables do not automatically appear in your
local terminal. The workflow does not provision Terraform infrastructure.

## 10. Push to dev and monitor deployment

Inspect branches before selecting one:

```bash
git fetch origin
git branch --all
```

`fetch` updates remote-tracking refs without merging. Choose one switch command:

| Branch state | Command |
| --- | --- |
| Local `dev` exists | `git switch dev` |
| Only `origin/dev` exists | `git switch --track origin/dev` |
| Neither exists | `git switch -c dev` |

Do not force the switch if local changes conflict. Review what will be committed:

```bash
helm lint ./infrastructure/helm/fastapi
git diff -- .github/workflows/deploy.yml
git add .github/workflows/deploy.yml infrastructure/helm/fastapi docs/HELM_INSTRUCTIONS.md
git diff --cached --stat
git commit -m "Document and configure Helm deployment on dev"
git push -u origin dev
```

`git add` stages only the named paths; the cached diff shows staged changes.
`commit` records them locally; `push -u` publishes `dev` and sets its upstream.
If those files are already committed, commit your actual new changes instead.
The workflow and chart must exist on the pushed branch. Repository rules and
organization Actions policies still apply.

```bash
gh run list --repo "$REPO" --workflow deploy.yml --branch dev --limit 5
gh run watch RUN_ID --repo "$REPO" --exit-status
```

Replace `RUN_ID` with the new run's numeric ID. `list` finds runs; `watch` follows
one and returns a failure exit code if it fails. After success:

```bash
helm list -n fastapi-helm
kubectl get pods,services -n fastapi-helm
```

These local checks require the AKS context from section 4. Open the Service's
external IP at `/docs`. Later pushes use the same release automatically. A local
manual Helm deployment to that release can be overwritten by the next CI run.

## 11. Troubleshooting

### Missing repository variable: AZURE_RESOURCE_GROUP

The workflow reads `vars.AZURE_RESOURCE_GROUP`, but that repository variable is
missing or empty. Setting an identically named secret is not sufficient.

```bash
gh variable set AZURE_RESOURCE_GROUP --repo "$REPO" --body fastapi-rg
gh variable list --repo "$REPO"
```

Set all six variables from section 8, then rerun the failed run. Environment-level
variables are unavailable unless the job uses that environment; this workflow
uses repository variables.

### AADSTS700213: No matching federated identity record

Azure rejected the token because the selected identity has no matching trust.
The reported `dev` subject includes `@11480002` and `@1353797397`; do not remove
them or substitute the old `main` branch subject.

```bash
az ad app show --id "$CLIENT_ID" \
  --query '{name:displayName,clientId:appId}' -o table
az ad app federated-credential list --id "$CLIENT_ID" -o json
```

Compare the exact issuer, subject, and audience with section 6 and the current
error. Use its full create/update commands, preserving other branch entries.
Then ensure GitHub selects that same application:

```bash
gh secret set AZURE_CLIENT_ID --repo "$REPO" --body "$CLIENT_ID"
```

Wait a few minutes for propagation and rerun. Trace/correlation IDs are useful
for Azure diagnostics, but are not values to put in the trust configuration.

### No subscriptions found for the deployment identity

This usually means the identity has no accessible Azure subscription through
role assignments, or the configured tenant/subscription is wrong. Creating an
application and OIDC trust does not grant Azure resource permissions. It can
happen after switching the GitHub client ID to a newly created application.

Sign in locally with your administrator identity and recover the correct context:

```bash
az login
az account set --subscription c9228dd2-1a35-4c93-a47c-60f9e28a7aec
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SP_OBJECT_ID=$(az ad sp show --id "$CLIENT_ID" --query id -o tsv)
az role assignment list --assignee "$SP_OBJECT_ID" --all \
  --query '[].{Role:roleDefinitionName,Scope:scope}' -o table
```

Stop if the identity cannot be found in this tenant. Retrieve `AKS_ID` and
`ACR_ID` using section 3, add missing roles using section 7, then align secrets:

```bash
gh secret set AZURE_CLIENT_ID --repo "$REPO" --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID --repo "$REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUBSCRIPTION_ID"
```

Wait for role propagation and rerun. Keep OIDC authentication. Setting
`allow-no-subscriptions: true` would allow a tenant-only login, not grant the
ACR/AKS access required by this deployment. Subscription-wide Contributor is
not necessary for the application deployment tasks documented here.

### Rerun or inspect a failed workflow

```bash
gh run list --repo "$REPO" --branch dev --limit 5
gh run view RUN_ID --repo "$REPO" --log-failed
gh run rerun RUN_ID --repo "$REPO" --failed
```

Replace `RUN_ID` before running. `view --log-failed` prints failed-step logs;
`rerun --failed` reruns failed jobs using the original commit. Secret, variable,
and Azure permission fixes do not require a new commit. Workflow code fixes need
a new commit/push to test the updated code.

### Helm timeout, image pull failure, or unhealthy pods

```bash
helm status fastapi-app -n fastapi-helm
kubectl get pods -n fastapi-helm
kubectl get events -n fastapi-helm --sort-by=.metadata.creationTimestamp
kubectl describe pod POD_NAME -n fastapi-helm
kubectl logs POD_NAME -n fastapi-helm
```

Replace `POD_NAME` with one from `get pods`. Events and `describe` show scheduling,
pull, and startup failures; logs show application output. For `ImagePullBackOff`,
check that the tag exists and the kubelet has `AcrPull`. For architecture errors,
rebuild with `--platform linux/amd64`. For Pending pods, inspect node capacity and
scheduling events. A Helm timeout can leave resources in place; inspect before
retrying. A ready Deployment alone does not prove every application endpoint works.

## 12. Switch deployment methods and clean up

### Use the original raw YAML method

The raw Deployment uses `latest`, so publish that tag before applying it:

```bash
az acr login --name fastapiacrdm
docker buildx build --platform linux/amd64 \
  -t fastapiacrdm.azurecr.io/dmfastapi-app:latest --push .
kubectl apply -n default -f infrastructure/kubernetes/deployment.yaml
kubectl apply -n default -f infrastructure/kubernetes/service.yaml
kubectl get svc fastapi-service -n default
```

`apply` creates or updates the raw resources; these remain separate from the Helm
release. The original `scripts/deploy.sh` also builds/pushes and applies raw YAML,
but uses admin credentials and has no explicit cross-platform build target.

If an existing raw Deployment already uses `latest`, pushing new bytes under that
same tag does not change its pod template. The earlier workflow used:

```bash
kubectl set image deployment/dmfastapi-app \
  fastapi=fastapiacrdm.azurecr.io/dmfastapi-app:latest -n default
kubectl rollout restart deployment/dmfastapi-app -n default
kubectl rollout status deployment/dmfastapi-app -n default
```

`set image` selects the container image; `restart` recreates pods to pull the
updated `latest`; `status` waits for rollout completion. These commands apply to
the raw Deployment, not the Helm release. CI now uses distinct SHA tags instead.

### Remove only a deployment you no longer want

To remove the Helm app:

```bash
helm uninstall fastapi-app -n fastapi-helm
```

This deletes the release's managed app resources. It leaves its namespace, AKS,
ACR, and raw YAML deployment intact. The next successful `dev` deployment will
install it again.

To remove only the original raw app, if it is in `default`:

```bash
kubectl delete -n default -f infrastructure/kubernetes/deployment.yaml
kubectl delete -n default -f infrastructure/kubernetes/service.yaml
```

These delete live resources, not the local YAML files. Run only when you intend
to stop that deployment. Both methods can coexist, but they consume extra pod
capacity and may provision additional public IP/load-balancing resources. App
uninstall is not infrastructure teardown; AKS/ACR costs can remain. Use the
project's separate infrastructure lifecycle guidance when finished with Azure.

## 13. Permission reference

| Identity / permission | Why it is used | Boundary |
| --- | --- | --- |
| Human: GitHub repository configuration access | Set Actions secrets/variables and push workflow changes. | Repository/token permissions and branch policies apply. |
| Human: Entra app-management rights | Create application/service principal and configure federation. | Entra directory permissions, distinct from Azure subscription RBAC. |
| Human: Azure resource-management rights | Terraform creates and manages infrastructure. | Resource group/subscription scopes appropriate to provisioning. |
| Human: role-assignment write permission | Grant deployment and kubelet roles. | Required at assignment scope or parent; Contributor alone is insufficient. |
| Actions `contents: read` | Checkout source and chart. | GitHub permission, not Azure access. |
| Actions `id-token: write` | Request short-lived OIDC token. | Azure must independently trust the token and authorize the identity. |
| Deployment principal: `AcrPush` | Push built images into ACR. | Assigned at this ACR; assumes its current non-ABAC role mode. |
| Deployment principal: AKS Cluster User | Retrieve cluster-user kubeconfig. | Assigned at this AKS resource; not by itself namespace-limited Kubernetes authorization. |
| AKS kubelet: `AcrPull` | Pull images onto nodes. | Terraform-managed assignment at ACR. |
| Kubernetes deployment access | Manage chart resources and Helm release Secrets. | Current non-Entra credentials are broad; Entra clusters need separate Kubernetes authorization. |

No permission is granted merely by storing an ID in GitHub. All three links must
agree: GitHub secrets select the identity, federation trusts the incoming token,
and Azure/Kubernetes roles authorize deployment actions.

## 14. Official references

- [Helm upgrade/install flags](https://docs.helm.sh/docs/helm/helm_upgrade/)
- [Azure Login and OIDC configuration](https://github.com/Azure/login)
- [GitHub OIDC subject formats](https://docs.github.com/en/actions/reference/security/oidc)
- [Azure federation matching and propagation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-considerations)
- [AKS kubeconfig access roles](https://learn.microsoft.com/en-us/azure/aks/control-kubeconfig-access)
- [GitHub CLI secret set](https://cli.github.com/manual/gh_secret_set)
- [GitHub CLI variable set](https://cli.github.com/manual/gh_variable_set)

This document reflects the repository and troubleshooting discussed on September
6, 2026. Local documentation validation is separate from live deployment success;
verify each cloud command's result before moving to the next step.
