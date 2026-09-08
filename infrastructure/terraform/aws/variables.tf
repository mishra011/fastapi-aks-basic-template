variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "cluster_name" {
  type    = string
  default = "fastapi-eks"
}
variable "kubernetes_version" {
  description = "Select an EKS version in standard support in your region."
  type        = string
  default     = "1.35"
}
variable "github_oidc_subject" {
  description = "Exact GitHub OIDC sub for the aws branch, including immutable IDs if enabled. No wildcards."
  type        = string
  validation {
    condition     = startswith(var.github_oidc_subject, "repo:") && endswith(var.github_oidc_subject, ":ref:refs/heads/aws") && length(regexall("[?*]", var.github_oidc_subject)) == 0
    error_message = "Provide the exact repo subject ending in :ref:refs/heads/aws without wildcards."
  }
}
variable "github_oidc_provider_arn" {
  description = "Existing account-wide GitHub OIDC provider ARN; null creates one."
  type        = string
  default     = null
}
variable "admin_principal_arn" {
  description = "Permanent IAM role/user ARN for bootstrap and local administration (not an STS session ARN)."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/.+", var.admin_principal_arn))
    error_message = "Use a permanent IAM role or user ARN."
  }
}
variable "namespace" {
  type    = string
  default = "fastapi"
}
variable "public_access_cidrs" {
  description = "API allowlist. GitHub-hosted runners need public API access; use a VPC runner before restricting this."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
variable "ecr_force_delete" {
  description = "Explicitly allow Terraform destroy to remove a repository containing images."
  type        = bool
  default     = false
}
