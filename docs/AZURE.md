> Legacy Azure reference. For the `aws` branch use [AWS deployment instructions](../README.md). These commands do not manage EKS.

# Azure Portal guide for FastAPI, AKS, ACR, and GitHub Actions

This is the portal companion to [HELM_INSTRUCTIONS.md](HELM_INSTRUCTIONS.md).
It maps the Azure CLI tasks from that guide to browser steps, explains the
permissions involved, and includes the login errors encountered during setup.
Use the existing `docs/` directory for both guides.

Open [Azure Portal](https://portal.azure.com). Menu labels can change; use the
portal search bar or a resource's menu search if a named item is not immediately
visible. This guide was prepared on September 6, 2026 using repository
configuration and official documentation, not a live inspection of your portal.

## 1. Project values and task map

| Item | Value |
| --- | --- |
| Subscription ID | `c9228dd2-1a35-4c93-a47c-60f9e28a7aec` |
| Resource group | `fastapi-rg` |
| AKS cluster | `fastapi-aks-cluster-dm` |
| ACR | `fastapiacrdm` |
| ACR login server | `fastapiacrdm.azurecr.io` |
| Image repository | `dmfastapi-app` |
| Deployment application name | `fastapi-github-dev-deploy` |
| GitHub repository | `mishra011/fastapi-aks-basic-template` |
| Deployment branch | `dev` |
| Helm release / namespace | `fastapi-app` / `fastapi-helm` |

Application display names are not unique. If you already created an application
under another name, find it by the client ID used in GitHub instead of creating
another identity.

| CLI task | Portal equivalent |
| --- | --- |
| `az login` | Sign in to Azure Portal; this signs in the browser only. |
| `az account set` | Switch directory and filter/select the intended subscription; this does not change local CLI context. |
| `az account show` | Subscriptions and Microsoft Entra ID overview pages. |
| `az aks show`, `az acr show` | Resource Overview, Properties, and JSON View. |
| `az ad app create` | Microsoft Entra ID > App registrations > New registration. |
| `az ad app list/show` | App registrations > All applications > selected application. |
| `az ad sp create/show` | Portal registration normally creates the service principal automatically; inspect it under Enterprise applications. |
| Federated credential list/create/update | App registration > Certificates & secrets > Federated credentials. |
| Role assignment list/create | Target resource > Access control (IAM). |
| `az aks stop/start` | AKS Overview > Stop/Start. |
| `az aks get-credentials` | AKS Connect provides connection instructions; a browser click does not configure local kubectl. |
| `az acr login` | No browser equivalent that authenticates local Docker; use CLI or the workflow. |

## 2. Sign in and select the directory and subscription

1. Sign in to Azure Portal with your human Azure account.
2. Open the account/directory selector, or **Portal settings > Directories + subscriptions**.
3. Switch to the directory containing the project subscription.
4. Search for **Subscriptions** and open the subscription with the ID listed above.
5. Check its status and copy its **Subscription ID**. This is `AZURE_SUBSCRIPTION_ID`.
6. Search for **Microsoft Entra ID** and open **Overview**.
7. Copy the **Tenant ID**. This is `AZURE_TENANT_ID`.

Why: the application, tenant secret, subscription secret, and Azure resources
must agree. Selecting a portal subscription filter controls what you see; it
does not grant access or update GitHub secrets.

If the subscription is absent, check the directory and subscription filters,
then ask its administrator to verify your account's access. Do not create a new
subscription as a workaround for the deployment identity's login error.

## 3. Find and inspect the existing infrastructure

1. Search for **Resource groups** and open **fastapi-rg**.
2. Confirm that **fastapiacrdm** and **fastapi-aks-cluster-dm** are present.
3. Open each resource and inspect **Overview** for subscription, group, location, and status.
4. Use **Properties** or **JSON View** to copy its full **Resource ID** if needed.

The AKS resource ID corresponds to `AKS_ID`; the registry ID corresponds to
`ACR_ID`. These identify the scopes used for resource-specific role assignments.

Terraform owns these resources in this project. Continue provisioning through
Terraform if they do not exist. Manually creating matching resources in the
portal does not add them to Terraform state, and changing Terraform-managed
properties in the portal can create drift. For learning the creation screens,
**Create a resource** exposes **Container Registry** and **Kubernetes Service**
wizards, but completing those wizards is an alternative provisioning path, not
a prerequisite for this existing deployment.

## 4. Create an app registration and obtain CLIENT_ID

Skip creation if the intended app already exists. To create it once:

1. Search for **Microsoft Entra ID**.
2. Select **App registrations > New registration**.
3. Enter **fastapi-github-dev-deploy** as the name.
4. Select **Accounts in this organizational directory only** for this project.
5. Leave **Redirect URI** empty; GitHub OIDC federation does not use an interactive redirect.
6. Select **Register**.
7. On the app's **Overview**, copy **Application (client) ID** as `CLIENT_ID`.
8. Confirm that **Directory (tenant) ID** matches the subscription's directory.

This replaces the app-creation command:

```bash
CLIENT_ID=$(az ad app create \
  --display-name fastapi-github-dev-deploy \
  --query appId -o tsv)
```

Do not create a client secret under **Client secrets**. The workflow uses a
federated credential instead. The application/client ID is an identifier, not a
password. Azure resource roles are configured through resource IAM, not the
app's **API permissions** page.

Permission: your tenant must allow you to register applications, or an Entra
administrator must grant appropriate app-management rights. Azure subscription
Owner and Entra application administrator are different permission systems.

## 5. Find an existing identity and its service principal object ID

To recover `CLIENT_ID` without creating a duplicate:

1. Open **Microsoft Entra ID > App registrations > All applications**.
2. Search by application name or a known client ID.
3. Open the intended app and copy **Application (client) ID** from **Overview**.
4. If names are duplicated, compare IDs with the identity you configured for GitHub.

To obtain `SP_OBJECT_ID`:

1. On the app's Overview, follow **Managed application in local directory**, if shown.
2. Alternatively, open **Microsoft Entra ID > Enterprise applications > All applications**.
3. Find the enterprise application with the same **Application ID** as your `CLIENT_ID`.
4. Copy its **Object ID** from Overview or Properties. This is `SP_OBJECT_ID`.

Registering an application through the portal normally creates the local service
principal automatically. That covers the outcome of the separate CLI command:

```bash
SP_OBJECT_ID=$(az ad sp create --id "$CLIENT_ID" --query id -o tsv)
```

Do not execute that command again when the principal already exists. An
application created previously using CLI may still need its service principal
created; if none exists, use the CLI creation step in the Helm guide rather than
registering a second app. Refresh and check directory/filters before concluding
it is missing. [Application registration reference](https://learn.microsoft.com/en-us/security/zero-trust/develop/app-registration).

| Portal field | Use |
| --- | --- |
| App registration: Application (client) ID | GitHub `AZURE_CLIENT_ID`. |
| App registration: Object ID | Identifies the app registration object, not the role recipient. |
| Enterprise application: Object ID | Service principal object ID; recipient of Azure roles. |
| Directory (tenant) ID | GitHub `AZURE_TENANT_ID`. |

## 6. Add the exact GitHub dev federated credential

1. Open the selected **App registration**.
2. Select **Certificates & secrets > Federated credentials**.
3. Inspect existing entries first. Keep any valid credential for `main`.
4. Select **Add credential** if no matching `dev` credential exists.
5. Choose **Other issuer** so you can enter the exact subject from the error.
6. Enter the values below and select **Add** or **Save**.

| Field | Exact value |
| --- | --- |
| Name | `github-dev` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject identifier | `repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/dev` |
| Audience | `api://AzureADTokenExchange` |
| Description, optional | `Allow GitHub Actions deployment from dev` |

Why **Other issuer**: a GitHub-specific wizard may generate a subject from names
and branch. Inspect that generated value if you use it; this repository's token
includes immutable numeric IDs, and the stored subject must match exactly.
The credential name is only a management label; issuer, subject, and audience
are the token-matching fields. Matching is case-sensitive.

If `github-dev` already exists, open it and edit the incorrect fields where the
portal exposes editing. If editing is unavailable, record its current settings,
delete only that incorrect entry, and recreate it with the table above. This
temporarily removes that entry's trust. Do not delete another branch's credential
or a correct matching entry stored under a different name.

Permission: app ownership or an appropriate Entra role that permits managing
the application's credentials. Creating this trust does not grant ACR or AKS
permissions. Allow a few minutes for changes to propagate.

The subject above comes from this project's actual `dev` error. If the repository
is renamed/transferred, or the workflow starts using a GitHub **environment**,
check the new token subject before changing trust. [Federation reference](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation).

## 7. Grant AcrPush to the GitHub deployment identity

1. Search for **Container registries** and open **fastapiacrdm**.
2. Select **Access control (IAM) > Role assignments**.
3. Search for the deployment application's name and inspect existing assignments.
4. If `AcrPush` is missing, select **Add > Add role assignment**.
5. On **Role**, search for and select **AcrPush**, then **Next**.
6. On **Members**, select **User, group, or service principal**.
7. Select **Select members**, find **fastapi-github-dev-deploy**, and select the matching identity.
8. Confirm the identity against the client/principal IDs you recorded, especially if names repeat.
9. Select **Review + assign**, review the registry scope, and complete the assignment.

Why: GitHub builds the container and needs to push it to this registry. This
matches `az role assignment create --role AcrPush --scope "$ACR_ID"`.
Opening IAM on the registry keeps the assignment scoped to ACR, rather than the
whole subscription. `AcrPush` applies to this project's current registry role
mode; a registry changed to ABAC repository permissions requires the applicable
repository roles instead.

Permission: the human making the assignment needs role-assignment write rights
at this resource or a parent scope, for example Owner or Role Based Access
Control Administrator, subject to any conditions. Contributor alone does not
grant those rights. A disabled **Add role assignment** button often indicates
insufficient permission. [IAM instructions](https://learn.microsoft.com/en-us/azure/role-based-access-control/quickstart-assign-role-user-portal).

## 8. Grant AKS Cluster User to the same identity

1. Open **Kubernetes services > fastapi-aks-cluster-dm**.
2. Select **Access control (IAM) > Role assignments** and inspect existing roles.
3. If missing, select **Add > Add role assignment**.
4. Select **Azure Kubernetes Service Cluster User Role**.
5. On **Members**, select **User, group, or service principal**.
6. Select the same deployment identity used in section 7.
7. Review and assign the role at this AKS resource's scope.

Why: the workflow obtains a cluster-user kubeconfig to deploy through Helm. This
matches `az role assignment create --role "Azure Kubernetes Service Cluster User Role" --scope "$AKS_ID"`.
Do not confuse it with **Azure Kubernetes Service RBAC Reader**, **RBAC Writer**,
or **Cluster Admin Role**; those have different purposes.

The cluster was previously observed with no Entra integration and local accounts
enabled. On that type of cluster, cluster-user credentials provide broad
Kubernetes access. This is not namespace-restricted authorization. Inspect
**Settings > Authentication and Authorization**, where available, or the
resource's **JSON View** for `properties.aadProfile` and
`properties.disableLocalAccounts`. Do not change authentication modes just to
clear a login error. Entra-enabled clusters require additional Kubernetes
authorization beyond Cluster User. [AKS credential access reference](https://learn.microsoft.com/en-us/azure/aks/control-kubeconfig-access).

## 9. Check the AKS kubelet's AcrPull permission

The GitHub service principal pushes images; the AKS kubelet identity pulls them.
Terraform already manages the kubelet's `AcrPull` assignment in this repository.

1. Open the AKS resource's **JSON View**.
2. Find `properties.identityProfile.kubeletidentity.objectId` and record it.
3. Open **fastapiacrdm > Access control (IAM) > Role assignments**.
4. Find the `AcrPull` assignment and compare its principal with the kubelet identity.

Do not substitute the cluster's control-plane identity or the GitHub deployment
identity. If the Terraform-managed assignment is missing, inspect and repair
through Terraform to keep state consistent. The portal's IAM **Add role
assignment** flow can assign `AcrPull` to the kubelet managed identity, but a
manual assignment must be reconciled with Terraform ownership rather than
silently duplicated.

## 10. Inspect images, deployments, and the public endpoint

### ACR images

1. Open **Container registries > fastapiacrdm**.
2. Select **Repositories** and open **dmfastapi-app**.
3. Inspect the tags. CI uses the commit SHA; manual Helm builds used `helm-...` timestamps.
4. Confirm the tag referenced by the deployment exists.

This checks published content, not local Docker authentication. Portal access to
the registry resource does not necessarily grant image-data access; repositories
require the applicable registry data permissions. Do not enable or copy admin
passwords to replace the workflow's OIDC authentication. [Repository browsing](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-repositories).

### AKS app health

1. Open **Kubernetes services > fastapi-aks-cluster-dm**.
2. Under **Kubernetes resources**, open **Workloads**.
3. Filter to **fastapi-helm** and inspect the **fastapi-app** Deployment and pods.
4. Open **Services and ingresses**, find **fastapi-app**, and inspect its external IP.
5. Visit `http://<EXTERNAL-IP>/docs` to check FastAPI.

The original raw YAML app normally appears in `default` as `dmfastapi-app` with
Service `fastapi-service`. Portal Kubernetes views need cluster connectivity and
Kubernetes permissions; failure to load a view alone does not prove the app is
down. Helm history and release operations remain best handled through Helm.
Avoid editing Helm-managed workload YAML in the portal, because the next Helm
upgrade can overwrite those edits. [AKS portal resource views](https://learn.microsoft.com/en-us/azure/aks/kubernetes-portal).

## 11. What still requires CLI or GitHub

| Task | Where to perform it |
| --- | --- |
| Authenticate local Docker (`az acr login`) | Local CLI; signing in to the portal does not log Docker in. |
| Configure local kubectl (`az aks get-credentials`) | AKS **Connect** provides commands to run locally or in Cloud Shell. |
| Build and push the local Dockerfile | Docker CLI or the existing GitHub Actions workflow. |
| Install/upgrade/uninstall the Helm release | Helm CLI or GitHub Actions; raw portal YAML deployment is not a Helm release. |
| Apply the project's Terraform | Terraform with the existing configuration and state. |
| Set repository secrets/variables | GitHub repository Settings, not Azure Portal. |
| Push commits or rerun Actions | Git/GitHub website or `gh`. |

Cloud Shell is a terminal hosted in the portal, not a replacement UI for every
command. It has its own filesystem and login context; it does not automatically
contain this repository, Terraform state, local Docker daemon, or local kubeconfig.

## 12. Complete GitHub setup in the browser

After the Azure steps, open the
[GitHub repository](https://github.com/mishra011/fastapi-aks-basic-template).

1. Open **Settings > Secrets and variables > Actions**.
2. Under **Secrets**, create or update these repository secrets using the portal values.

| Secret | Portal value |
| --- | --- |
| `AZURE_CLIENT_ID` | App registration > Application (client) ID. |
| `AZURE_TENANT_ID` | Matching Directory (tenant) ID. |
| `AZURE_SUBSCRIPTION_ID` | Subscription containing AKS and ACR. |

3. Under **Variables**, create these repository variables.

| Variable | Value |
| --- | --- |
| `AZURE_RESOURCE_GROUP` | `fastapi-rg` |
| `AZURE_AKS_CLUSTER` | `fastapi-aks-cluster-dm` |
| `ACR_NAME` | `fastapiacrdm` |
| `IMAGE_NAME` | `dmfastapi-app` |
| `HELM_RELEASE` | `fastapi-app` |
| `KUBE_NAMESPACE` | `fastapi-helm` |

Use repository-level entries. The current workflow has no GitHub job environment
and therefore does not use environment-scoped values. You need GitHub repository
configuration access; Azure roles do not grant that access.

4. Ensure the chart and workflow are committed on `dev`, then push a change.
5. Open **Actions > Deploy FastAPI to AKS** and inspect the run.
6. After a settings-only fix, open the failed run and use **Re-run jobs > Re-run failed jobs**.

A rerun uses the original commit. Workflow code changes require a new push to test
the updated workflow. The workflow needs `contents: read` for checkout and
`id-token: write` to request the OIDC token; neither grants Azure permissions.

## 13. Resolve the errors from this setup

### Missing repository variable: AZURE_RESOURCE_GROUP

Open GitHub **Settings > Secrets and variables > Actions > Variables**. Add
`AZURE_RESOURCE_GROUP` with value `fastapi-rg` and verify all six variables above.
An identically named secret does not satisfy a workflow `vars` reference. Rerun
the failed job after saving.

### AADSTS700213: No matching federated identity record

1. Open the app registration selected by GitHub's `AZURE_CLIENT_ID`.
2. Open **Certificates & secrets > Federated credentials**.
3. Compare issuer, subject, and audience with the exact error and section 6.
4. Correct the `dev` entry, keeping its numeric repository/owner IDs.
5. Preserve valid credentials for other branches and allow propagation before rerunning.

If correct trust already exists, verify that the GitHub secret selects that app
and the tenant secret points to its directory. Do not create another app merely
because federation failed.

### No subscriptions found

1. Verify the GitHub subscription ID against **Subscriptions > Overview**.
2. Verify the tenant ID against the directory containing that subscription.
3. Verify the client ID against the app with the correct federated credential.
4. Inspect ACR IAM for `AcrPush` assigned to that app's service principal.
5. Inspect AKS IAM for **Azure Kubernetes Service Cluster User Role** assigned to the same principal.
6. Add missing assignments through sections 7 and 8; wait a few minutes and rerun.

The common cause is switching GitHub to a new app that has OIDC trust but no
Azure role assignments. Creating an app is not granting subscription access.
`allow-no-subscriptions: true` would not grant access to deploy to AKS or push to
ACR. Do not change authentication type or grant subscription-wide Contributor as
the first fix.

### Permission denied while configuring Azure

| Failing portal task | Permission to check |
| --- | --- |
| New registration / credential editing | Entra app registration policy, ownership, or appropriate Entra app-management role. |
| Add role assignment disabled | Azure role-assignment write permission at resource or parent scope; Contributor alone is insufficient. |
| Cannot see resource | Directory/subscription filter and resource read access. |
| Cannot browse repositories | Registry data-plane permissions and network restrictions. |
| Cannot browse Kubernetes resources | Kubernetes authorization and API network reachability. |

Use **Access control (IAM) > Check access** to inspect access at a resource. Role
assignments on parent scopes can be inherited; check those before adding new ones.

## 14. Stop/start AKS and understand cleanup

To pause the learning cluster:

1. Open **Kubernetes services > fastapi-aks-cluster-dm > Overview**.
2. Select **Stop** and confirm the intended cluster.
3. Follow portal notifications and refresh until the cluster reports stopped.

To resume:

1. Open the same Overview and select **Start**.
2. Wait until it reports running and the operation completes.
3. Check workloads and the Service endpoint again before deploying.

These correspond to `az aks stop` and `az aks start`. They require the cluster's
stop/start management actions, not merely Cluster User credential access. The
GitHub deployment identity is not assigned lifecycle-management roles by this
guide. Stop the AKS cluster through AKS controls, not by manually deallocating its
individual node virtual machines. Follow the service's stop/start timing guidance
before cycling it repeatedly. [AKS stop/start reference](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster).

Stopping interrupts FastAPI and prevents normal deployments until restart. It is
not deletion or a guarantee of zero cost: disks, registry storage, networking,
and other retained resources can still incur charges. Use **Cost Management >
Cost analysis** at the appropriate subscription/group scope to inspect spending;
billing data can lag.

For permanent teardown, prefer the project's Terraform/state-aware cleanup
workflow. **Resource groups > fastapi-rg > Delete resource group** is the portal's
destructive alternative, not part of setup: it deletes resources in that group
and leaves Terraform state needing reconciliation. AKS also uses a managed node
resource group, and Entra app registrations exist outside resource groups, so
verify actual remaining resources rather than assuming one deletion removes
everything. Removing a Helm release is an app-level operation; it does not
delete AKS or ACR.

## 15. Completion checks

- The intended app's client ID and tenant match the GitHub secrets.
- Its enterprise application's object ID is the principal receiving the Azure roles.
- The federated credential matches the exact `dev` subject, issuer, and audience.
- ACR IAM grants the deployment identity `AcrPush`; AKS IAM grants it Cluster User.
- The separate kubelet identity retains its Terraform-managed `AcrPull` assignment.
- GitHub has the three repository secrets and six repository variables.
- AKS is running, a `dev` workflow run succeeds, and the image tag appears in ACR.
- `fastapi-app` is healthy in `fastapi-helm`, and its external IP serves `/docs`.

The portal and CLI operate on the same Azure objects. An identity or assignment
created with one is visible through the other; there is no need to create a
second copy when switching interfaces.
