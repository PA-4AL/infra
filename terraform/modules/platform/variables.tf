variable "project_id" {
  description = "Identifiant du projet GCP"
  type        = string
}

variable "region" {
  description = "Région des ressources"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Nom de l'environnement (préfixe toutes les ressources) : dev, prod…"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "environment doit être en minuscules, 2 à 8 caractères."
  }
}

variable "domain" {
  description = "Domaine racine (app./api./auth. y seront mappés). null = URLs *.run.app"
  type        = string
  default     = null
}

variable "deployer_service_account" {
  description = "Compte de service de la pipeline de déploiement (sortie sa_deploy_email du bootstrap)"
  type        = string
}

variable "image_tag" {
  description = "Tag d'image utilisé à la CRÉATION des services ; ensuite la pipeline de déploiement décide (ignore_changes)"
  type        = string
  default     = "latest"
}

variable "subnet_cidr" {
  description = "Plage du sous-réseau Cloud Run"
  type        = string
  default     = "10.20.0.0/24"
}

variable "db_tier" {
  description = "Gabarit Cloud SQL"
  type        = string
  default     = "db-f1-micro"
}

variable "db_deletion_protection" {
  description = "Empêche un terraform destroy d'emporter la base"
  type        = bool
  default     = true
}

variable "keycloak_min_instances" {
  description = "1 en prod (évite un cold start de ~25 s au login), 0 en dev"
  type        = number
  default     = 1
}

variable "backend_min_instances" {
  description = "0 = scale-to-zero (gratuit mais cold start JVM de ~15 s)"
  type        = number
  default     = 0
}

variable "worker_min_instances" {
  description = "1 pour un consommateur pull : à 0 il ne consommerait jamais la file"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Plafond d'instances (garde-fou de facturation)"
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# Budget de connexions à la base — voir le calcul dans main.tf
#
# Une ressource `terraform_data` vérifie la cohérence de ces quatre valeurs au
# `plan` : un budget intenable échoue avant d'atteindre la production.
# ---------------------------------------------------------------------------
variable "db_max_connections" {
  description = "Plafond PostgreSQL (le défaut d'un f1-micro, ~25, est trop bas pour plusieurs révisions Cloud Run)"
  type        = number
  default     = 60
}

variable "backend_db_pool_size" {
  description = "Connexions HikariCP par instance de backend (défaut Spring : 10, bien trop pour un f1-micro)"
  type        = number
  default     = 3
}

variable "keycloak_db_pool_size" {
  description = "Connexions Agroal par instance de Keycloak (défaut Keycloak : 100)"
  type        = number
  default     = 5
}

variable "db_connections_reservees_humains" {
  description = "Marge pour les accès d'exploitation : tunnel bastion, WebStorm, psql"
  type        = number
  default     = 8
}

variable "worker_log_level" {
  description = "Niveau de log du worker Rust"
  type        = string
  default     = "info"
}

variable "keycloak_admin_username" {
  description = "Compte administrateur Keycloak créé au premier démarrage"
  type        = string
  default     = "admin"
}

variable "alert_email" {
  description = "Adresse notifiée en cas de 5xx anormaux (null = pas d'alerte)"
  type        = string
  default     = null
}

# Origines réelles, utilisées quand aucun domaine n'est configuré : les URLs
# Cloud Run ne sont pas devinables de façon fiable (ancien format à hash).
variable "app_origin_override" {
  description = "URL réelle du frontend (sortie `urls` du premier apply)"
  type        = string
  default     = null
}

variable "api_origin_override" {
  description = "URL réelle du backend"
  type        = string
  default     = null
}

variable "auth_origin_override" {
  description = "URL réelle de Keycloak"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Bastion d'administration — outil d'exploitation, pas une brique de la plateforme
# ---------------------------------------------------------------------------
variable "bastion_enabled" {
  description = "Crée une VM bastion (arrêtée) pour joindre Cloud SQL en SSH depuis un poste"
  type        = bool
  default     = false
}

variable "bastion_zone" {
  description = "Zone de la VM bastion"
  type        = string
  default     = "europe-west1-b"
}

variable "bastion_ssh_source_ranges" {
  description = "Adresses autorisées à joindre le port 22 du bastion"
  type        = list(string)
  default     = []
}

variable "bastion_ssh_public_key" {
  description = "Clé publique OpenSSH déposée sur le bastion"
  type        = string
  default     = ""
}

variable "bastion_ssh_user" {
  description = "Utilisateur Linux associé à la clé"
  type        = string
  default     = "alex"
}
