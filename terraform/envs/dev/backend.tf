# État Terraform partagé (créé par terraform/bootstrap).
# Le nom du bucket dépend du projet : il est fourni au `terraform init`.
#
#   terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
terraform {
  backend "gcs" {
    prefix = "envs/dev"
  }
}
