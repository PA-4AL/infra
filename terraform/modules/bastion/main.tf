# =============================================================================
# Bastion d'administration — accès à Cloud SQL depuis un poste de développement.
#
# La base n'a pas d'IP publique : elle n'est joignable que depuis le VPC. Cette
# petite VM sert de point d'entrée SSH pour ouvrir un tunnel vers l'IP privée de
# l'instance, ce que sait faire nativement l'onglet SSH/SSL d'une Data Source
# WebStorm/DataGrip.
#
# Deux garde-fous de coût et de sécurité :
#   - la VM est créée **arrêtée** (`desired_status = TERMINATED`) : on ne paie
#     que le disque (~0,40 €/mois) tant qu'on ne s'en sert pas ;
#   - le port 22 n'est ouvert qu'aux adresses explicitement listées.
#
# Elle n'est pas nécessaire au fonctionnement de la plateforme : c'est un outil
# d'exploitation, activable par `bastion_enabled`.
# =============================================================================

variable "prefix" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "network_id" { type = string }
variable "subnet_id" { type = string }

variable "ssh_source_ranges" {
  description = "Adresses autorisées à joindre le port 22 (jamais 0.0.0.0/0)"
  type        = list(string)
  validation {
    condition     = !contains(var.ssh_source_ranges, "0.0.0.0/0")
    error_message = "Ouvrir le SSH à Internet entier est refusé : listez des adresses précises."
  }
}

variable "ssh_public_key" {
  description = "Clé publique au format OpenSSH, préfixée du nom d'utilisateur"
  type        = string
}

variable "ssh_user" {
  description = "Nom d'utilisateur Linux associé à la clé"
  type        = string
  default     = "alex"
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.prefix}-bastion-ssh"
  network = var.network_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["${var.prefix}-bastion"]
  description   = "SSH vers le bastion d'administration, depuis les adresses autorisées uniquement"
}

resource "google_compute_instance" "bastion" {
  name         = "${var.prefix}-bastion"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["${var.prefix}-bastion"]

  # Créée à l'arrêt : on la démarre à la demande (cf. docs/EXPLOITATION.md).
  desired_status = "TERMINATED"

  boot_disk {
    initialize_params {
      # Debian 12, image maintenue par Google, 10 Go standard (le moins cher).
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_id
    # IP publique éphémère : nécessaire pour un SSH direct depuis le poste.
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
    # Pas de serveur de métadonnées exposé à l'applicatif, pas de scope large.
    enable-oslogin = "FALSE"
  }

  service_account {
    # Aucun compte de service : le bastion n'a besoin d'aucun droit GCP, il ne
    # sert qu'à relayer du TCP vers l'IP privée de la base.
    scopes = []
  }

  # La VM est un outil jetable : on doit pouvoir la recréer sans cérémonie.
  allow_stopping_for_update = true

  lifecycle {
    # Démarrer ou arrêter la VM à la main ne doit pas être considéré comme une
    # dérive par Terraform.
    ignore_changes = [desired_status]
  }
}

output "name" { value = google_compute_instance.bastion.name }
output "zone" { value = google_compute_instance.bastion.zone }
output "public_ip" {
  description = "IP publique éphémère — vide tant que la VM est arrêtée"
  value       = try(google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip, "")
}
