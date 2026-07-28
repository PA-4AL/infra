# =============================================================================
# Messagerie asynchrone — Pub/Sub entre le backend et le worker Rust.
#
#   backend  --publie-->  topic-demandes  --pull-->   worker (Cloud Run)
#   worker   --publie-->  topic-reponses  --push-->   backend /internal/jobs/callback
#
# Le worker fait du PULL (il consomme quand il est prêt, cf. worker/src/main.rs),
# le backend reçoit les réponses en PUSH authentifié par jeton OIDC : pas de
# polling côté backend, et l'endpoint peut vérifier l'appelant.
#
# Les fichiers Excel circulent en base64 dans le message (cf.
# worker/src/tasks/import_excel.rs) : la limite Pub/Sub est de 10 Mo par message.
# =============================================================================

variable "prefix" { type = string }
variable "backend_callback_url" {
  type        = string
  description = "URL complète de l'endpoint de callback du backend"
}
variable "push_service_account" {
  type        = string
  description = "Compte de service dont Pub/Sub signera les jetons OIDC"
}
variable "ack_deadline" {
  type    = number
  default = 120 # un export Excel volumineux peut prendre du temps
}

resource "google_pubsub_topic" "demandes" {
  name = "${var.prefix}-demandes"
}

resource "google_pubsub_topic" "reponses" {
  name = "${var.prefix}-reponses"
}

# File de rebut : après 5 échecs, le message y est déposé au lieu de tourner
# en boucle et de saturer le worker.
resource "google_pubsub_topic" "dlq" {
  name = "${var.prefix}-dlq"
}

resource "google_pubsub_subscription" "worker_demandes" {
  name  = "${var.prefix}-worker-demandes"
  topic = google_pubsub_topic.demandes.id

  ack_deadline_seconds       = var.ack_deadline
  message_retention_duration = "86400s" # 24 h
  expiration_policy {
    ttl = "" # ne jamais expirer, même si le worker est arrêté un moment
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_subscription" "backend_reponses" {
  name  = "${var.prefix}-backend-reponses"
  topic = google_pubsub_topic.reponses.id

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = var.backend_callback_url

    # Le backend vérifie ce jeton : personne d'autre ne peut appeler l'endpoint.
    oidc_token {
      service_account_email = var.push_service_account
      audience              = var.backend_callback_url
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }
}

# Sans ce droit, Pub/Sub ne peut pas déposer dans la file de rebut.
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  topic  = google_pubsub_topic.dlq.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  subscription = google_pubsub_subscription.worker_demandes.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

data "google_project" "current" {}

output "topic_demandes" { value = google_pubsub_topic.demandes.id }
output "topic_reponses" { value = google_pubsub_topic.reponses.id }
output "subscription_demandes" { value = google_pubsub_subscription.worker_demandes.id }
output "dlq_topic" { value = google_pubsub_topic.dlq.id }
