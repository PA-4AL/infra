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
