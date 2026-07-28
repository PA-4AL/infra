# =============================================================================
# Module Cloud Run v2 réutilisable (frontend, backend, worker, keycloak).
#
# Point de conception important : l'IMAGE n'est pas gérée par Terraform après la
# création (`ignore_changes`). Terraform décrit l'infrastructure ; c'est la
# pipeline de déploiement qui promeut une version d'image. Sans cela, chaque
# `terraform apply` ferait régresser les services vers l'image du fichier .tf.
# =============================================================================

variable "name" { type = string }
variable "region" { type = string }
variable "image" { type = string }
variable "service_account" { type = string }

variable "env" {
  type        = map(string)
  default     = {}
  description = "Variables d'environnement en clair"
}

variable "secret_env" {
  type        = map(string)
  default     = {}
  description = "Variables d'environnement lues dans Secret Manager : NOM => secret_id"
}

variable "network_id" {
  type    = string
  default = null
}
variable "subnet_id" {
  type    = string
  default = null
}

variable "public" {
  type        = bool
  default     = false
  description = "true = accessible sans authentification (frontend, backend, keycloak)"
}

variable "min_instances" {
  type    = number
  default = 0
}
variable "max_instances" {
  type    = number
  default = 3
}
variable "cpu" {
  type    = string
  default = "1"
}
variable "memory" {
  type    = string
  default = "512Mi"
}
variable "cpu_always_allocated" {
  type        = bool
  default     = false
  description = "true pour un consommateur de file : il travaille hors requête HTTP"
}
variable "startup_probe_path" {
  type        = string
  default     = null
  description = "Chemin HTTP de la sonde de démarrage (null = simple test du port)"
}
variable "startup_timeout_seconds" {
  type    = number
  default = 120
}
variable "request_timeout" {
  type    = string
  default = "60s"
}

resource "google_cloud_run_v2_service" "this" {
  name     = var.name
  location = var.region

  # INTERNAL_ONLY pour le worker : il n'a aucune raison d'être joignable
  # depuis Internet, seule sa sonde interne écoute.
  ingress             = var.public ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false

  template {
    service_account = var.service_account
    timeout         = var.request_timeout

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Accès direct au VPC (Cloud SQL en IP privée) sans connecteur payant.
    dynamic "vpc_access" {
      for_each = var.network_id == null ? [] : [1]
      content {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces {
          network    = var.network_id
          subnetwork = var.subnet_id
        }
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        # cpu_idle = false → CPU allouée en permanence (consommateur Pub/Sub).
        cpu_idle          = !var.cpu_always_allocated
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      dynamic "startup_probe" {
        for_each = var.startup_probe_path == null ? [] : [1]
        content {
          http_get {
            path = var.startup_probe_path
          }
          initial_delay_seconds = 10
          period_seconds        = 5
          timeout_seconds       = 3
          # Keycloak et Spring démarrent lentement : on tolère un long réveil
          # plutôt que de tuer la révision en boucle.
          failure_threshold = ceil(var.startup_timeout_seconds / 5)
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    # La version déployée est décidée par la pipeline de déploiement.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.public ? 1 : 0
  project  = google_cloud_run_v2_service.this.project
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "uri" { value = google_cloud_run_v2_service.this.uri }
output "name" { value = google_cloud_run_v2_service.this.name }
