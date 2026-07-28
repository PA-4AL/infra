output "frontend_url" {
  description = "URL du frontend (run.app)"
  value       = module.frontend.uri
}

output "backend_url" {
  description = "URL du backend (run.app)"
  value       = module.backend.uri
}

output "keycloak_url" {
  description = "URL de Keycloak (run.app)"
  value       = module.keycloak.uri
}

output "app_origin" {
  description = "Origine publique du frontend (domaine si configuré)"
  value       = local.app_origin
}

output "auth_origin" {
  description = "Origine publique de Keycloak (domaine si configuré)"
  value       = local.auth_origin
}

output "service_names" {
  description = "Noms des services Cloud Run, pour les pipelines de déploiement"
  value = {
    frontend = module.frontend.name
    backend  = module.backend.name
    worker   = module.worker.name
    keycloak = module.keycloak.name
  }
}

output "runtime_service_account" {
  description = "Identité d'exécution des services"
  value       = google_service_account.runtime.email
}

output "database_private_ip" {
  description = "IP privée de l'instance Cloud SQL"
  value       = module.database.private_ip
}

output "database_instance" {
  description = "Nom de l'instance Cloud SQL"
  value       = module.database.instance_name
}

output "secrets" {
  description = "Secrets à alimenter ou à consulter (gcloud secrets versions …)"
  value = {
    db_app_password       = module.database.app_password_secret_id
    db_keycloak_password  = module.database.keycloak_password_secret_id
    keycloak_admin        = google_secret_manager_secret.keycloak_admin.secret_id
    sso_google_client_id  = "${local.prefix}-google-client-id"
    sso_google_secret     = "${local.prefix}-google-client-secret"
    sso_discord_client_id = "${local.prefix}-discord-client-id"
    sso_discord_secret    = "${local.prefix}-discord-client-secret"
  }
}

output "dns_records" {
  description = "Enregistrements DNS à créer chez le registrar (aucun proxy/CDN devant ces entrées)"
  value = var.domain == null ? [] : [
    for name, mapping in google_cloud_run_domain_mapping.this :
    {
      nom   = mapping.name
      type  = try(mapping.status[0].resource_records[0].type, "CNAME")
      cible = try(mapping.status[0].resource_records[0].rrdata, "ghs.googlehosted.com.")
    }
  ]
}

output "pubsub" {
  description = "Ressources de messagerie"
  value = {
    topic_demandes        = module.messaging.topic_demandes
    topic_reponses        = module.messaging.topic_reponses
    subscription_demandes = module.messaging.subscription_demandes
    dlq                   = module.messaging.dlq_topic
  }
}
