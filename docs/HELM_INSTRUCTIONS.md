# Helm on AWS EKS

See the [AWS setup guide](../README.md) for provisioning and configuration.

- `scripts/deploy.sh` builds an AMD64 image, pushes it to ECR, and deploys Helm.
- `IMAGE_TAG=EXISTING_TAG scripts/deploy-helm.sh` deploys an existing image.
- The namespace must already exist; bootstrap creates it.
- Image repository/tag come from configuration, not a hardcoded account.
- Service annotations and `loadBalancerClass: eks.amazonaws.com/nlb` target EKS Auto Mode.
- The chart has resource requests/limits and `/health` probes.

```bash
helm lint infrastructure/helm/fastapi
helm template fastapi-app infrastructure/helm/fastapi --namespace fastapi
helm history fastapi-app -n fastapi
helm rollback fastapi-app PREVIOUS_REVISION -n fastapi --wait --timeout 15m
```

For another Kubernetes platform, override `service.loadBalancerClass` to an empty string and `service.annotations` as appropriate. The chart's default image is a local placeholder; deployment scripts always supply the ECR image.
