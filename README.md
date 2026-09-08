# FastAPI on AWS EKS

The `aws` branch deploys FastAPI to **Amazon EKS Auto Mode**, stores Docker images in **ECR**, and uses **Helm + GitHub Actions** for CI/CD. GitHub authenticates using OIDC; no AWS access keys are stored in GitHub.

## Architecture

Terraform creates a VPC across two availability zones, public subnets for the Network Load Balancer, private subnets for worker nodes, one NAT gateway, EKS Auto Mode, ECR, and IAM/OIDC access. Auto Mode manages compute, networking, storage, and load balancing. The service exposes HTTP port 80 and forwards to FastAPI port 8000; `/health` is used for readiness, liveness, and load balancer checks.

The single NAT gateway is a development cost/availability tradeoff, not a highly available production design. EKS control plane, Auto Mode/EC2 nodes, NAT, public IPv4, NLB, data transfer, and ECR storage incur charges. The API endpoint is public with IAM authentication for GitHub-hosted runners; private access is also enabled. For production, use runners inside the VPC, restrict `public_access_cidrs`, and add HTTPS using ACM.

## 1. Prerequisites

Install AWS CLI v2, Terraform >=1.5, Docker with Buildx, kubectl matching the cluster minor version, Helm 4.2.4, and GitHub CLI. Sign in with your AWS administrative identity and GitHub account:

```bash
aws sso login --profile YOUR_PROFILE
export AWS_PROFILE=YOUR_PROFILE
aws sts get-caller-identity
gh auth login
```

The AWS identity needs permission to provision VPC, EKS, ECR, IAM roles/policies/OIDC providers, and pass the EKS/node roles. `admin_principal_arn` must be the permanent IAM role/user ARN of the identity you will use for bootstrap and local deployment, not the `arn:aws:sts::...:assumed-role/...` session ARN shown by STS. For SSO, use the corresponding IAM role ARN including its path.

## 2. Configure AWS Terraform

**Use `infrastructure/terraform/aws` only.** The parent `infrastructure/terraform` contains the legacy Azure configuration and local Azure state. They remain separate so switching clouds cannot accidentally destroy Azure resources. AWS creation does not remove existing Azure resources or their charges.

```bash
cp infrastructure/terraform/aws/terraform.tfvars.example infrastructure/terraform/aws/terraform.tfvars
```

Edit `terraform.tfvars` with your AWS region, permanent admin ARN, and desired names. The example defaults to Mumbai (`ap-south-1`) and Kubernetes `1.35`; verify regional availability/quota before provisioning. Local tfvars and state are gitignored. Back up state securely; use an encrypted, versioned S3 backend with state locking before collaborating on infrastructure. CI validates Terraform only; it does not apply or destroy infrastructure or need access to its state.

The example GitHub subject uses this repository's prefix returned by GitHub's OIDC API:

```text
repo:mishra011@11480002/fastapi-aks-basic-template@1353797397:ref:refs/heads/aws
```

For another repository, inspect its configuration:

```bash
gh api repos/OWNER/REPO/actions/oidc/customization/sub
```

Use the exact `sub_claim_prefix` plus `:ref:refs/heads/aws` when using the default branch subject. For a custom claim template, use the actual token subject. Do not add a GitHub Environment without also updating the trust policy: environments change the subject. This Terraform configuration intentionally requires the `aws` branch subject.

If your AWS account already has the GitHub OIDC provider, set `github_oidc_provider_arn` in tfvars to reuse it. Inspect existing providers with `aws iam list-open-id-connect-providers`.

## 3. Create infrastructure and namespace

```bash
./setup_scripts/bootstrap_aws.sh
```

Review Terraform's plan and enter `yes` to provision. Bootstrap also creates the application namespace using your admin identity. The GitHub role has ECR push access for this repository, EKS DescribeCluster access, and EKS admin access limited to the app namespace. It cannot create namespaces or provision infrastructure.

## 4. Link GitHub Actions

Once bootstrap completes:

```bash
./setup_scripts/configure_github_aws.sh
```

This reads Terraform outputs and sets these values on the GitHub repository:

| GitHub setting | Value |
| --- | --- |
| Secret `AWS_ROLE_ARN` | OIDC deployment role ARN |
| Variable `AWS_REGION` | AWS region |
| Variable `EKS_CLUSTER_NAME` | EKS cluster name |
| Variable `ECR_REPOSITORY_URL` | Full ECR repository URL, without tag |
| Variable `KUBE_NAMESPACE` | Application namespace (default `fastapi`) |
| Variable `HELM_RELEASE` | Helm release (default `fastapi-app`) |

Push the updated code to `aws`. `.github/workflows/deploy.yml` runs application tests, Helm lint/render, Terraform validation, shell syntax checks, and a container build. After validation passes on an `aws` push, it authenticates through AWS OIDC, builds/pushes a Linux AMD64 image, deploys Helm, waits for readiness and checks the public `/health` endpoint. Pull requests into `aws` run validation only. Manual dispatch is supported once GitHub exposes the workflow from the repository default branch; choose `aws` as the ref.

Tags contain commit SHA, run ID, and attempt number so reruns work with immutable ECR tags. Keep old images needed for Helm rollbacks; prune older images deliberately as storage grows. `azure/setup-helm` only installs the Helm binary and requires no Azure account.

## 5. Deploy locally

```bash
./scripts/deploy.sh
```

This builds/pushes an AMD64 image (also from Apple Silicon), then deploys and health-checks it. To deploy an existing ECR tag:

```bash
IMAGE_TAG=YOUR_EXISTING_TAG ./scripts/deploy-helm.sh
```

Scripts resolve configuration from AWS Terraform outputs unless environment variables override them. They use temporary kubeconfigs to avoid deploying to an unrelated current context.

## 6. Inspect or roll back

```bash
aws eks update-kubeconfig --region ap-south-1 --name fastapi-eks
kubectl get pods,svc -n fastapi
kubectl get events -n fastapi --sort-by=.lastTimestamp
helm history fastapi-app -n fastapi
helm rollback fastapi-app PREVIOUS_REVISION -n fastapi --wait --timeout 15m
```

AWS returns a load balancer **hostname**, not a fixed external IP. Open `http://HOSTNAME/` or `/docs`. If health verification fails after Helm succeeds, inspect NLB targets and security groups; the script reports failure but does not automatically roll back. See [troubleshooting](docs/TROUBLESHOOTING.md).

## 7. Optional raw Kubernetes manifests

Helm is the CI/CD deployment path. For a separate learning deployment using an existing ECR image:

```bash
export IMAGE_URI=ACCOUNT.dkr.ecr.ap-south-1.amazonaws.com/fastapi-eks/fastapi:EXISTING_TAG
kubectl set image --local -f infrastructure/kubernetes/deployment.yaml "fastapi=$IMAGE_URI" -o yaml | kubectl apply -n fastapi -f -
kubectl apply -n fastapi -f infrastructure/kubernetes/service.yaml
kubectl rollout status -n fastapi deployment/dmfastapi-app --timeout=15m
```

This creates a second deployment and NLB if Helm is already installed, with additional charges. Remove it with `kubectl delete -n fastapi -f infrastructure/kubernetes/` when done.

## 8. Tear down AWS

ECR defaults to protecting non-empty repositories. If you intend to delete all stored images, set `ecr_force_delete = true` in tfvars and apply that change first. Then:

```bash
./setup_scripts/destroy_infra.sh
```

The script asks for `DESTROY`, removes the Helm release and optional raw Service while EKS can still clean up NLBs, refuses to continue if other LoadBalancer Services remain, and asks for Terraform destroy approval. It checks that Terraform state is empty afterward. Check AWS for any manually created resources or persistent volumes before considering all charges stopped. Azure teardown must be performed separately with the original Azure configuration/state.

## Local application

```bash
docker compose up --build
```

Open `http://localhost:8000`. The application code is cloud-independent.

## References

- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode NLB annotations](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-nlb.html)
- [GitHub OIDC subject formats](https://docs.github.com/en/actions/reference/security/oidc)
- [AWS credentials action](https://github.com/aws-actions/configure-aws-credentials)
