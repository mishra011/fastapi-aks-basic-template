# GitHub Actions to AWS EKS

Follow [README steps 2–4](../README.md) to provision infrastructure and populate GitHub configuration.

The `aws` branch workflow validates the app/container, chart, Terraform and scripts. Pushes then assume the Terraform-created AWS role using OIDC (`id-token: write`), push an immutable ECR tag, deploy Helm, and verify `/health` through the NLB. Pull requests never receive AWS deployment credentials.

Run `./setup_scripts/configure_github_aws.sh` after bootstrap to set `AWS_ROLE_ARN`, `AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REPOSITORY_URL`, `KUBE_NAMESPACE`, and `HELM_RELEASE`. No Azure credentials or long-lived AWS keys are used. Terraform stays local with its own state; the pipeline does not provision infrastructure.

If OIDC fails, match the trust policy to the repository's exact `sub_claim_prefix` and `:ref:refs/heads/aws` suffix. This repository uses an immutable-ID prefix. Adding a GitHub Environment changes the subject and requires a deliberate trust-policy update.
