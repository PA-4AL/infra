# Valeurs de l'environnement de production.

project_id = "pa-tournament-4al"
region     = "europe-west1"

# Domaine racine (OVH). Les origines publiques en découlent :
#   app.patournament.fr · api.patournament.fr · auth.patournament.fr
domain = "patournament.fr"

# Sortie `sa_deploy_email` du bootstrap.
deployer_service_account = "gh-deploy@pa-tournament-4al.iam.gserviceaccount.com"

# Adresse notifiée en cas de 5xx anormaux.
alert_email = "alexandrehelleux@hotmail.fr"

# --- Arbitrages de coût ------------------------------------------------------
# Ce compte de facturation n'a PAS de crédits d'essai. Budget assumé : ~10 € sur
# une période d'ouverture d'environ 10 jours. Estimation retenue :
#   Cloud SQL db-f1-micro + 10 Go HDD ....... ~2,4 €
#   Keycloak, 1 instance minimum ............ ~3,2 €
#   Worker, 1 instance minimum (CPU allouée)  ~3,2 €
#   Frontend, backend, Pub/Sub, registre .... ~0 € (offre gratuite)
#                                             ------
#                                             ~8,8 €
# Une alerte de facturation à 10 € est posée sur le compte (50 / 90 / 100 %).

# Keycloak toujours chaud : pas de démarrage à froid de ~25 s sur l'écran de
# connexion, choix assumé même sans crédits.
keycloak_min_instances = 1

# Le worker consomme la file en pull : à 0 il ne traiterait jamais rien.
worker_min_instances = 1

# Environnement temporaire, destruction prévue à la fin de la période : la
# protection empêcherait `terraform destroy` de nettoyer la base.
db_deletion_protection = false

# --- Bastion d'administration -------------------------------------------------
# VM créée ARRÊTÉE : on ne paie que le disque (~0,40 €/mois) tant qu'on ne la
# démarre pas. Elle sert à ouvrir un tunnel SSH vers l'IP privée de Cloud SQL
# depuis WebStorm/DataGrip (cf. docs/EXPLOITATION.md).
bastion_enabled = true

# IP publique du poste de développement. À mettre à jour si elle change
# (adresse résidentielle dynamique) : `curl -4 -s https://ifconfig.me`.
bastion_ssh_source_ranges = ["90.3.95.151/32"]

bastion_ssh_user       = "alex"
bastion_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHk98zxKs0IHMbVLDpkceuOMjcw9OEm+8zeXtU5eqMO alexandrehelleux@hotmail.fr"
