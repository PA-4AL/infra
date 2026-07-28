# =============================================================================
# Bootstrap — appliqué UNE SEULE FOIS, en local, par un compte propriétaire.
#
# Résout le problème de l'œuf et de la poule : la pipeline Terraform a besoin
# d'un bucket d'état, d'un compte de service et d'une fédération d'identité…
# qui sont eux-mêmes des ressources cloud. On les crée donc ici, avec un état
# local (committé volontairement dans .gitignore, cf. README).
#
#   cd terraform/bootstrap
#   terraform init && terraform apply -var project_id=<PROJECT_ID>
#
# Contenu : APIs, bucket d'état, Artifact Registry, Workload Identity
# Federation pour GitHub Actions, et les trois comptes de service (tf-admin,
# gh-ci, gh-deploy) avec le principe du moindre privilège.
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

variable "project_id" {
  description = "Identifiant du projet GCP"
  type        = string
}

variable "region" {
  description = "Région des ressources régionales (Cloud Run, Artifact Registry, Cloud SQL)"
  type        = string
  default     = "europe-west1"
}

variable "github_owner" {
  description = "Organisation GitHub propriétaire des repos"
  type        = string
  default     = "PA-4AL"
}

variable "github_repos" {
  description = "Repos autorisés à s'authentifier par fédération d'identité"
  type        = list(string)
  default     = ["infra", "backend", "worker", "frontend"]
}

locals {
  # APIs indispensables. Les activer par IAC évite le classique
  # « ça marche chez moi » après une activation manuelle dans la console.
  services = [
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.services)
  service  = each.value

  # On ne coupe pas les APIs si on détruit ce module : d'autres ressources
  # (et la facturation) en dépendent.
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# État Terraform distant
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "tfstate" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  # Versionné : un `terraform apply` malheureux reste rattrapable.
  versioning { enabled = true }
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition { num_newer_versions = 20 }
    action { type = "Delete" }
  }
}

# ---------------------------------------------------------------------------
# Registre d'images (source de vérité pour Cloud Run)
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "pa" {
  location      = var.region
  repository_id = "pa"
  format        = "DOCKER"
  description   = "Images des services PA Tournament"

  # Les images de dev s'accumulent vite : on ne garde pas les non-taguées.
  cleanup_policies {
    id     = "supprime-les-images-non-taguees"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 jours
    }
  }

  depends_on = [google_project_service.enabled]
}

# ---------------------------------------------------------------------------
# Workload Identity Federation : GitHub Actions s'authentifie par jeton OIDC.
# Aucune clé de compte de service n'est créée ni stockée dans GitHub.
# ---------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
  description               = "Fédération d'identité pour les pipelines PA-4AL"

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Sans cette condition, N'IMPORTE QUEL dépôt GitHub public pourrait demander
  # un jeton pour ce provider.
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ---------------------------------------------------------------------------
# Comptes de service
# ---------------------------------------------------------------------------

# 1) Terraform (pipeline IAC du repo infra)
resource "google_service_account" "tf_admin" {
  account_id   = "tf-admin"
  display_name = "Terraform (pipeline IAC)"
}

# 2) Build/push d'images (pipelines CI des 4 repos)
resource "google_service_account" "gh_ci" {
  account_id   = "gh-ci-build"
  display_name = "GitHub Actions — build & push des images"
}

# 3) Déploiement Cloud Run (pipelines de mise en production)
resource "google_service_account" "gh_deploy" {
  account_id   = "gh-deploy"
  display_name = "GitHub Actions — déploiement Cloud Run"
}

locals {
  # Rôles de tf-admin : large, mais borné au projet et utilisé uniquement par la
  # pipeline IAC (une pipeline Terraform doit pouvoir créer/détruire).
  tf_admin_roles = [
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/pubsub.admin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.admin",
    "roles/compute.networkAdmin",
    "roles/servicenetworking.networksAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/storage.admin",
    "roles/monitoring.editor",
  ]

  # gh-deploy : peut déployer une révision et rien d'autre.
  gh_deploy_roles = [
    "roles/run.developer",
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "tf_admin" {
  for_each = toset(local.tf_admin_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.tf_admin.email}"
}

resource "google_project_iam_member" "gh_deploy" {
  for_each = toset(local.gh_deploy_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.gh_deploy.email}"
}

# gh-ci n'a besoin que d'écrire dans le registre.
resource "google_artifact_registry_repository_iam_member" "gh_ci_writer" {
  location   = google_artifact_registry_repository.pa.location
  repository = google_artifact_registry_repository.pa.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.gh_ci.email}"
}

# Note : le droit d'attacher l'identité d'exécution aux révisions (actAs) est
# accordé par le module `platform`, qui crée cette identité par environnement.

# tf-admin gère l'état Terraform dans le bucket.
resource "google_storage_bucket_iam_member" "tf_admin_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tf_admin.email}"
}

# ---------------------------------------------------------------------------
# Qui peut emprunter quel compte de service, depuis quel repo
# ---------------------------------------------------------------------------
locals {
  repo_principals = {
    for repo in var.github_repos :
    repo => "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${repo}"
  }
}

# Les 4 repos poussent des images…
resource "google_service_account_iam_member" "ci_impersonation" {
  for_each           = local.repo_principals
  service_account_id = google_service_account.gh_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value
}

# …et déploient leur propre service.
resource "google_service_account_iam_member" "deploy_impersonation" {
  for_each           = local.repo_principals
  service_account_id = google_service_account.gh_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value
}

# Seul le repo infra pilote Terraform.
resource "google_service_account_iam_member" "tf_impersonation" {
  service_account_id = google_service_account.tf_admin.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.repo_principals["infra"]
}

# ---------------------------------------------------------------------------
# Sorties : à reporter dans les variables/secrets GitHub (cf. DEPLOY.md)
# ---------------------------------------------------------------------------
output "workload_identity_provider" {
  description = "Valeur de la variable GitHub WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "sa_ci_email" {
  description = "Compte de service des jobs de build (GitHub : WIF_SA_CI)"
  value       = google_service_account.gh_ci.email
}

output "sa_deploy_email" {
  description = "Compte de service des jobs de déploiement (GitHub : WIF_SA_DEPLOY)"
  value       = google_service_account.gh_deploy.email
}

output "sa_terraform_email" {
  description = "Compte de service de la pipeline Terraform (GitHub : WIF_SA_TERRAFORM)"
  value       = google_service_account.tf_admin.email
}

output "tfstate_bucket" {
  description = "Bucket d'état Terraform (à reporter dans envs/*/backend.tf)"
  value       = google_storage_bucket.tfstate.name
}

output "artifact_registry" {
  description = "Préfixe des images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pa.repository_id}"
}
