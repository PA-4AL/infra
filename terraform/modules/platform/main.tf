# =============================================================================
# Plateforme PA Tournament — composition complète d'un environnement.
#
# Le même code sert pour dev et pour prod : seules les valeurs changent
# (terraform.tfvars). C'est ce qui permet de recréer un environnement complet
# sans rien cliquer dans la console.
# =============================================================================

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.41"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  prefix = "pa-${var.environment}"

  # Noms Pub/Sub calculés (et non lus depuis les ressources) : cela évite un
  # cycle de dépendances entre les services et les abonnements.
  topic_demandes        = "projects/${var.project_id}/topics/${local.prefix}-demandes"
  topic_reponses        = "projects/${var.project_id}/topics/${local.prefix}-reponses"
  subscription_demandes = "projects/${var.project_id}/subscriptions/${local.prefix}-worker-demandes"

  registry = "${var.region}-docker.pkg.dev/${var.project_id}/pa"

  # URLs publiques. Elles ne peuvent PAS être lues depuis les sorties des
  # services : le backend a besoin de l'origine du frontend (CORS) et le
  # frontend de celle du backend (appels API) — Terraform y verrait un cycle.
  # Ordre de résolution, du plus fiable au moins fiable :
  #   1. le domaine, quand il est configuré (cas visé en production) ;
  #   2. les overrides `*_origin_override`, à renseigner après le premier apply
  #      avec les URLs réelles (sortie `urls`) — c'est la seconde passe
  #      documentée dans DEPLOY.md ;
  #   3. à défaut, le format déterministe des URLs Cloud Run. ATTENTION : les
  #      projets dont les services utilisent l'ancien format à hash
  #      (SERVICE-xxxxxxxxxx-ew.a.run.app) ne le respectent pas — d'où la
  #      seconde passe obligatoire tant qu'aucun domaine n'est branché.
  predicted_url = {
    for svc in ["frontend", "backend", "keycloak"] :
    svc => "https://${local.prefix}-${svc}-${data.google_project.current.number}.${var.region}.run.app"
  }

  app_origin = coalesce(
    var.domain == null ? null : "https://app.${var.domain}",
    var.app_origin_override,
    local.predicted_url["frontend"],
  )
  api_origin = coalesce(
    var.domain == null ? null : "https://api.${var.domain}",
    var.api_origin_override,
    local.predicted_url["backend"],
  )
  auth_origin = coalesce(
    var.domain == null ? null : "https://auth.${var.domain}",
    var.auth_origin_override,
    local.predicted_url["keycloak"],
  )
}

# ---------------------------------------------------------------------------
# Identités d'exécution
# ---------------------------------------------------------------------------
resource "google_service_account" "runtime" {
  account_id   = "${local.prefix}-run"
  display_name = "Exécution des services Cloud Run (${var.environment})"
}

# Identité dont Pub/Sub signe les jetons OIDC des livraisons push.
resource "google_service_account" "pubsub_push" {
  account_id   = "${local.prefix}-push"
  display_name = "Pub/Sub → backend (jetons OIDC, ${var.environment})"
}

# La pipeline de déploiement doit pouvoir attacher l'identité d'exécution.
resource "google_service_account_iam_member" "deploy_actas_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deployer_service_account}"
}

data "google_project" "current" {}

# L'agent de service Pub/Sub doit pouvoir créer des jetons pour l'identité push.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.pubsub_push.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Réseau et base de données
# ---------------------------------------------------------------------------
module "network" {
  source = "../network"

  prefix      = local.prefix
  region      = var.region
  subnet_cidr = var.subnet_cidr
}

module "database" {
  source = "../database"

  prefix              = local.prefix
  region              = var.region
  tier                = var.db_tier
  network_id          = module.network.network_id
  psa_connection      = module.network.psa_connection
  deletion_protection = var.db_deletion_protection
}

# ---------------------------------------------------------------------------
# Secrets applicatifs
# ---------------------------------------------------------------------------
resource "random_password" "keycloak_admin" {
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "keycloak_admin" {
  secret_id = "${local.prefix}-keycloak-admin-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "keycloak_admin" {
  secret      = google_secret_manager_secret.keycloak_admin.id
  secret_data = random_password.keycloak_admin.result
}

# Identifiants SSO : créés vides ici (valeurs déposées à la main, jamais dans
# git) et consommés par scripts/keycloak-configure.sh.
resource "google_secret_manager_secret" "sso" {
  for_each = toset([
    "google-client-id", "google-client-secret",
    "discord-client-id", "discord-client-secret",
  ])
  secret_id = "${local.prefix}-${each.value}"
  replication {
    auto {}
  }
}

locals {
  runtime_secrets = concat(
    [
      module.database.app_password_secret_id,
      module.database.keycloak_password_secret_id,
      google_secret_manager_secret.keycloak_admin.secret_id,
    ],
    [for s in google_secret_manager_secret.sso : s.secret_id],
  )
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each  = toset(local.runtime_secrets)
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

# ---------------------------------------------------------------------------
# Droits Pub/Sub de l'identité d'exécution
# ---------------------------------------------------------------------------
resource "google_pubsub_topic_iam_member" "runtime_publisher" {
  for_each = toset(["${local.prefix}-demandes", "${local.prefix}-reponses"])
  topic    = each.value
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${google_service_account.runtime.email}"

  depends_on = [module.messaging]
}

resource "google_pubsub_subscription_iam_member" "runtime_subscriber" {
  subscription = "${local.prefix}-worker-demandes"
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.runtime.email}"

  depends_on = [module.messaging]
}

# ---------------------------------------------------------------------------
# Services Cloud Run
# ---------------------------------------------------------------------------

# Keycloak — min_instances=1 en prod : un cold start de ~25 s sur l'écran de
# connexion est la pire première impression possible.
module "keycloak" {
  source = "../service"

  name            = "${local.prefix}-keycloak"
  region          = var.region
  image           = "${local.registry}/keycloak:${var.image_tag}"
  service_account = google_service_account.runtime.email
  public          = true

  network_id = module.network.network_id
  subnet_id  = module.network.subnet_id

  min_instances           = var.keycloak_min_instances
  max_instances           = 2
  memory                  = "1Gi"
  cpu                     = "1"
  startup_probe_path      = "/realms/pa-tournament/.well-known/openid-configuration"
  startup_timeout_seconds = 240

  # Uniquement des options de RUNTIME : l'image est lancée avec
  # `start --optimized`, et lui passer une option de build (health-enabled,
  # db, features…) fait sortir le conteneur en exit(2) — vérifié.
  env = merge(
    {
      KC_DB_URL      = "jdbc:postgresql://${module.database.private_ip}:5432/keycloak"
      KC_DB_USERNAME = module.database.keycloak_user
      # Derrière le frontal Cloud Run, Keycloak doit faire confiance aux
      # en-têtes X-Forwarded-* pour générer les bonnes URLs d'issuer.
      KC_PROXY_HEADERS            = "xforwarded"
      KC_HTTP_ENABLED             = "true"
      KC_BOOTSTRAP_ADMIN_USERNAME = var.keycloak_admin_username
    },
    # Le hostname n'est fixé que si l'URL publique est connue de façon fiable
    # (domaine, ou origine relevée après le premier apply). Sinon on désactive
    # la vérification stricte : un KC_HOSTNAME vide empêche le démarrage.
    var.domain == null && var.auth_origin_override == null
    ? { KC_HOSTNAME_STRICT = "false" }
    : { KC_HOSTNAME = local.auth_origin }
  )

  secret_env = {
    KC_DB_PASSWORD              = module.database.keycloak_password_secret_id
    KC_BOOTSTRAP_ADMIN_PASSWORD = google_secret_manager_secret.keycloak_admin.secret_id
  }
}

module "backend" {
  source = "../service"

  name            = "${local.prefix}-backend"
  region          = var.region
  image           = "${local.registry}/backend:${var.image_tag}"
  service_account = google_service_account.runtime.email
  public          = true

  network_id = module.network.network_id
  subnet_id  = module.network.subnet_id

  min_instances           = var.backend_min_instances
  max_instances           = var.max_instances
  memory                  = "1Gi"
  startup_probe_path      = "/actuator/health/readiness"
  startup_timeout_seconds = 180

  env = {
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://${module.database.private_ip}:5432/pa"
    SPRING_DATASOURCE_USERNAME = module.database.app_user
    KEYCLOAK_ISSUER_URI        = "${local.auth_origin}/realms/pa-tournament"
    APP_CORS_ALLOWED_ORIGINS   = local.app_origin
    # Messagerie avec le worker : publication des demandes et vérification des
    # jetons OIDC des livraisons push sur /internal/v1/jobs/callback.
    APP_PUBSUB_ENABLED          = "true"
    GCP_PROJECT_ID              = var.project_id
    PUBSUB_TOPIC_DEMANDS        = local.topic_demandes
    PUBSUB_PUSH_AUDIENCE        = "${local.api_origin}/internal/v1/jobs/callback"
    PUBSUB_PUSH_SERVICE_ACCOUNT = google_service_account.pubsub_push.email
  }

  secret_env = {
    SPRING_DATASOURCE_PASSWORD = module.database.app_password_secret_id
  }
}

# Worker — consommateur pull : jamais appelé en HTTP, donc pas d'ingress public,
# CPU allouée en permanence et une instance en permanence.
module "worker" {
  source = "../service"

  name            = "${local.prefix}-worker"
  region          = var.region
  image           = "${local.registry}/worker:${var.image_tag}"
  service_account = google_service_account.runtime.email
  public          = false

  network_id = module.network.network_id
  subnet_id  = module.network.subnet_id

  min_instances        = var.worker_min_instances
  max_instances        = 2
  memory               = "512Mi"
  cpu_always_allocated = true

  env = {
    GCP_PROJECT_ID              = var.project_id
    PUBSUB_SUBSCRIPTION_DEMANDS = local.subscription_demandes
    PUBSUB_TOPIC_RESPONSES      = local.topic_reponses
    RUST_LOG                    = var.worker_log_level
  }
}

module "frontend" {
  source = "../service"

  name            = "${local.prefix}-frontend"
  region          = var.region
  image           = "${local.registry}/frontend:${var.image_tag}"
  service_account = google_service_account.runtime.email
  public          = true

  min_instances      = 0
  max_instances      = var.max_instances
  memory             = "256Mi" # nginx statique
  startup_probe_path = "/health"

  # Config injectée au démarrage du conteneur (une image, tous les environnements).
  env = {
    API_URL            = local.api_origin
    KEYCLOAK_URL       = local.auth_origin
    KEYCLOAK_REALM     = "pa-tournament"
    KEYCLOAK_CLIENT_ID = "pa-frontend"
  }
}

# ---------------------------------------------------------------------------
# Messagerie (après le backend : l'abonnement push a besoin de son URL)
# ---------------------------------------------------------------------------
module "messaging" {
  source = "../messaging"

  prefix               = local.prefix
  backend_callback_url = "${local.api_origin}/internal/v1/jobs/callback"
  push_service_account = google_service_account.pubsub_push.email
}

# ---------------------------------------------------------------------------
# Domaines personnalisés + certificats gérés par Google (gratuits)
# ---------------------------------------------------------------------------
locals {
  domain_mappings = var.domain == null ? {} : {
    app  = module.frontend.name
    api  = module.backend.name
    auth = module.keycloak.name
  }
}

resource "google_cloud_run_domain_mapping" "this" {
  for_each = local.domain_mappings

  location = var.region
  name     = "${each.key}.${var.domain}"

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = each.value
  }
}

# ---------------------------------------------------------------------------
# Garde-fou budget : une alerte vaut mieux qu'une mauvaise surprise
# ---------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "run_errors" {
  count        = var.alert_email == null ? 0 : 1
  display_name = "${local.prefix} — erreurs 5xx Cloud Run"
  combiner     = "OR"

  conditions {
    display_name = "Taux de 5xx élevé"
    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_revision\"",
        "metric.type = \"run.googleapis.com/request_count\"",
        "metric.label.response_code_class = \"5xx\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].id]
}

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email == null ? 0 : 1
  display_name = "Alertes ${local.prefix}"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}
