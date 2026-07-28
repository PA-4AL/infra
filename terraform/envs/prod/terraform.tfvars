# Valeurs de l'environnement de production.

project_id = "pa-tournament-4al"
region     = "europe-west1"

# Domaine racine ; laisser commenté tant qu'il n'est pas acheté et vérifié
# (les services répondent alors sur leurs URLs *.run.app).
# domain = "exemple.fr"

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
