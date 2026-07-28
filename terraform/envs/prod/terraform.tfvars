# Valeurs de l'environnement de production.
# À compléter avant le premier apply (cf. docs/DEPLOY.md, étape 1).

project_id = "REMPLACER-PAR-LE-PROJECT-ID"
region     = "europe-west1"

# Domaine racine ; laisser null pour un premier déploiement sur *.run.app,
# puis renseigner une fois le domaine acheté et vérifié.
# domain = "exemple.fr"

# Sortie `sa_deploy_email` du bootstrap.
deployer_service_account = "gh-deploy@REMPLACER-PAR-LE-PROJECT-ID.iam.gserviceaccount.com"

# Adresse notifiée en cas de 5xx anormaux.
# alert_email = "alexandrehelleux@hotmail.fr"
