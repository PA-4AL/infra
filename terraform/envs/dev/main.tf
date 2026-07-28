# =============================================================================
# Environnement DÉVELOPPEMENT (non déployé par défaut : le code IAC doit
# simplement prouver qu'il supporte plusieurs environnements sans duplication).
#
# Ce fichier ne fait que câbler le module `platform` : toute la logique est
# partagée avec dev, seules les valeurs diffèrent (terraform.tfvars).
# =============================================================================

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.41"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west1"
}
variable "domain" {
  type    = string
  default = null
}
variable "deployer_service_account" { type = string }
variable "alert_email" {
  type    = string
  default = null
}

# Origines réelles des services, à renseigner après le premier apply tant
# qu'aucun domaine n'est branché (cf. docs/DEPLOY.md, seconde passe).
variable "app_origin_override" {
  type    = string
  default = null
}
variable "api_origin_override" {
  type    = string
  default = null
}
variable "auth_origin_override" {
  type    = string
  default = null
}

# Arbitrages de coût, pilotés depuis terraform.tfvars.
variable "keycloak_min_instances" {
  type    = number
  default = 0
}
variable "worker_min_instances" {
  type    = number
  default = 0
}
variable "backend_min_instances" {
  type    = number
  default = 0
}
variable "max_instances" {
  type    = number
  default = 2
}
variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}
variable "db_deletion_protection" {
  type    = bool
  default = false
}

module "platform" {
  source = "../../modules/platform"

  project_id               = var.project_id
  region                   = var.region
  environment              = "dev"
  domain                   = var.domain
  deployer_service_account = var.deployer_service_account
  alert_email              = var.alert_email

  # Dev : tout scale à zéro, base non protégée (jetable), plafonds bas.
  keycloak_min_instances = var.keycloak_min_instances
  worker_min_instances   = var.worker_min_instances
  backend_min_instances  = var.backend_min_instances
  max_instances          = var.max_instances
  db_tier                = var.db_tier
  db_deletion_protection = var.db_deletion_protection
  subnet_cidr            = "10.30.0.0/24"

  app_origin_override  = var.app_origin_override
  api_origin_override  = var.api_origin_override
  auth_origin_override = var.auth_origin_override
}

output "urls" {
  value = {
    frontend = module.platform.frontend_url
    backend  = module.platform.backend_url
    keycloak = module.platform.keycloak_url
    public   = module.platform.app_origin
  }
}

output "service_names" { value = module.platform.service_names }
output "dns_records" { value = module.platform.dns_records }
output "secrets" { value = module.platform.secrets }
output "database_private_ip" { value = module.platform.database_private_ip }
output "pubsub" { value = module.platform.pubsub }
