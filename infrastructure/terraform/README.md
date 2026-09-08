# Terraform cloud boundaries

On the `aws` branch, use `terraform -chdir=infrastructure/terraform/aws ...` or the AWS bootstrap script. That directory owns independent AWS state.

This parent directory retains the previous Azure configuration and lock file for existing Azure state. Do not run it to provision AWS, copy Azure state into `aws/`, or delete the state while Azure resources still exist. AWS setup does not tear down Azure infrastructure.
