# AWS EKS troubleshooting

- **OIDC AccessDenied:** compare `gh api repos/OWNER/REPO/actions/oidc/customization/sub` with Terraform's `github_oidc_subject`; verify audience `sts.amazonaws.com`, branch `aws`, and secret `AWS_ROLE_ARN`. Avoid broad wildcard trust.
- **OIDC provider already exists:** set `github_oidc_provider_arn` to the existing provider ARN and re-plan.
- **kubectl Unauthorized/Forbidden:** verify the AWS identity, EKS access entry, and namespace. Run bootstrap as the configured permanent admin role. CI cannot create namespaces.
- **API timeout:** GitHub-hosted runners need the public endpoint and an allowed source CIDR; restrictive/private endpoints need a runner with VPC connectivity.
- **Pods pending:** inspect events, Auto Mode node pools, EC2 quota/capacity, and private-subnet NAT routes.
- **ImagePullBackOff:** verify full ECR URL/tag, node ECR pull permissions, region/account, and outbound network connectivity.
- **exec format error:** images and chart nodes are set to AMD64; use `docker buildx build --platform linux/amd64`.
- **NLB pending or health timeout:** check public subnet `kubernetes.io/role/elb` tags, Auto Mode cluster IAM policies, Service events, target groups, and port 8000 health checks. DNS/target registration can lag pod readiness.
- **Immutable tag error:** CI includes run ID/attempt in tags. For custom local runs use a new `IMAGE_TAG`.
- **Destroy fails on ECR:** explicitly apply `ecr_force_delete=true` only if all stored images can be removed, then retry cleanup.
- **VPC deletion blocked:** inspect leftover LoadBalancer Services, NLBs, ENIs and volumes. Remove Kubernetes-managed objects while the cluster controller is still available.

```bash
kubectl get pods,svc -n fastapi
kubectl describe pods -n fastapi
kubectl get events -n fastapi --sort-by=.lastTimestamp
kubectl logs -n fastapi -l app.kubernetes.io/instance=fastapi-app --tail=100
```
