output "aws_region" { value = var.aws_region }
output "cluster_name" { value = aws_eks_cluster.main.name }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "github_role_arn" { value = aws_iam_role.github.arn }
output "namespace" { value = var.namespace }
output "vpc_id" { value = aws_vpc.main.id }
output "github_oidc_subject" { value = var.github_oidc_subject }
