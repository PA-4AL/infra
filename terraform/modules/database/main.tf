# =============================================================================
# Base de données — Cloud SQL PostgreSQL, IP privée uniquement.
#
# Deux bases sur une seule instance (une seule facture) :
#   - `pa`       : données applicatives, migrées par Liquibase au démarrage du backend
#   - `keycloak` : stockage du serveur d'identité
#
# Les mots de passe sont générés ici et stockés dans Secret Manager : ils
# n'apparaissent ni dans git, ni dans les variables d'environnement en clair
# d'une définition de service.
# =============================================================================

terraform {
  required_providers {
    google = { source = "hashicorp/google" }
    random = { source = "hashicorp/random" }
  }
}

variable "prefix" { type = string }
variable "region" { type = string }
variable "tier" {
  type        = string
  description = "Gabarit de l'instance (db-f1-micro en prod : ~7,70 $/mois)"
}
variable "network_id" { type = string }
variable "psa_connection" {
  type        = string
  description = "Dépendance sur le peering : l'instance ne peut pas être créée avant"
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "disk_size" {
  type    = number
  default = 10
}

resource "google_sql_database_instance" "main" {
  name                = "${var.prefix}-db"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier = var.tier
    # Édition explicite : sans cela l'API bascule sur ENTERPRISE_PLUS, qui
    # refuse les gabarits à cœur partagé (« Invalid Tier (db-f1-micro) for
    # (ENTERPRISE_PLUS) Edition »).
    edition = "ENTERPRISE"
    # Une seule zone : pas de haute disponibilité (doublerait la facture) —
    # acceptable pour un projet scolaire, à documenter comme limite connue.
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = var.disk_size
    disk_autoresize   = true

    ip_configuration {
      # Aucune IP publique : la base n'est joignable que depuis le VPC.
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = false # journalisation WAL : coût de stockage
      backup_retention_settings {
        retained_backups = 7
      }
    }

    maintenance_window {
      day          = 7 # dimanche
      hour         = 4
      update_track = "stable"
    }

    database_flags {
      # Les traces de connexion facilitent le diagnostic des accès Cloud Run.
      name  = "log_connections"
      value = "on"
    }
  }

  # Sans le peering, la création échoue avec une erreur peu explicite.
  depends_on = [var.psa_connection]
}

resource "google_sql_database" "app" {
  name     = "pa"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_database" "keycloak" {
  name     = "keycloak"
  instance = google_sql_database_instance.main.name
}

# ---------------------------------------------------------------------------
# Comptes et secrets
# ---------------------------------------------------------------------------
resource "random_password" "app" {
  length  = 32
  special = false # évite les échappements dans les URL JDBC
}

resource "random_password" "keycloak" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "pa"
  instance = google_sql_database_instance.main.name
  password = random_password.app.result
}

resource "google_sql_user" "keycloak" {
  name     = "keycloak"
  instance = google_sql_database_instance.main.name
  password = random_password.keycloak.result
}

resource "google_secret_manager_secret" "app_password" {
  secret_id = "${var.prefix}-db-app-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app_password" {
  secret      = google_secret_manager_secret.app_password.id
  secret_data = random_password.app.result
}

resource "google_secret_manager_secret" "keycloak_password" {
  secret_id = "${var.prefix}-db-keycloak-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "keycloak_password" {
  secret      = google_secret_manager_secret.keycloak_password.id
  secret_data = random_password.keycloak.result
}

output "private_ip" { value = google_sql_database_instance.main.private_ip_address }
output "instance_name" { value = google_sql_database_instance.main.name }
output "connection_name" { value = google_sql_database_instance.main.connection_name }
output "app_user" { value = google_sql_user.app.name }
output "keycloak_user" { value = google_sql_user.keycloak.name }
output "app_password_secret_id" { value = google_secret_manager_secret.app_password.secret_id }
output "keycloak_password_secret_id" { value = google_secret_manager_secret.keycloak_password.secret_id }
