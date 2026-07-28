# =============================================================================
# Réseau — VPC dédié + plage réservée pour l'accès privé aux services Google.
#
# Objectif : Cloud SQL sans adresse IP publique. Les services Cloud Run
# l'atteignent par « Direct VPC egress » (aucun connecteur d'accès VPC
# serverless à payer, ~8 $/mois économisés) et la base n'est jamais exposée
# sur Internet.
# =============================================================================

variable "prefix" { type = string }
variable "region" { type = string }
variable "subnet_cidr" {
  type        = string
  default     = "10.20.0.0/24"
  description = "Plage du sous-réseau utilisé par les instances Cloud Run"
}

resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "run" {
  name          = "${var.prefix}-run"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  # Permet aux instances d'atteindre les APIs Google sans IP publique.
  private_ip_google_access = true
}

# Plage cédée à Google pour y placer l'instance Cloud SQL (private services access).
resource "google_compute_global_address" "psa" {
  name          = "${var.prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}

output "network_id" { value = google_compute_network.vpc.id }
output "subnet_id" { value = google_compute_subnetwork.run.id }
output "psa_connection" { value = google_service_networking_connection.psa.id }
