# Infrastructure as Code — Terraform

Toutes les ressources cloud du projet sont décrites ici. Aucune ressource ne
doit être créée à la main dans la console : si elle n'est pas dans ce dossier,
elle n'existe pas.

## Arborescence

```
terraform/
├── bootstrap/          # appliqué UNE fois, en local (état local)
│   └── main.tf         # APIs, bucket d'état, Artifact Registry, WIF, comptes de service
├── modules/
│   ├── network/        # VPC + sous-réseau + plage d'accès privé (PSA)
│   ├── database/       # Cloud SQL PostgreSQL (IP privée), bases pa + keycloak, secrets
│   ├── messaging/      # topics/abonnements Pub/Sub + file de rebut
│   ├── service/        # module Cloud Run v2 réutilisable
│   └── platform/       # composition d'un environnement complet
└── envs/
    ├── dev/            # mêmes ressources, valeurs économes (non déployé)
    └── prod/           # environnement de production
```

Un seul code décrit les deux environnements : `envs/*/main.tf` ne fait qu'appeler
`modules/platform` avec d'autres valeurs. C'est ce que demande la consigne
(« supporter plusieurs environnements ») sans doubler la facture.

## Différences dev / prod

| | dev | prod |
|---|---|---|
| Keycloak `min-instances` | 0 (cold start accepté) | 1 (login instantané) |
| Worker `min-instances` | 0 | 1 (consommateur pull) |
| Plafond d'instances | 2 | 4 |
| Protection de la base | désactivée | activée |
| Sous-réseau | 10.30.0.0/24 | 10.20.0.0/24 |

## Séquence de première mise en place

```bash
# 1) Bootstrap (une seule fois, avec un compte propriétaire du projet)
cd bootstrap
terraform init
terraform apply -var project_id=<PROJECT_ID>
terraform output          # → à reporter dans les variables GitHub

# 2) Environnement de production
cd ../envs/prod
# renseigner project_id et deployer_service_account dans terraform.tfvars
terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
terraform plan
terraform apply           # ~15 min, dont la création de l'instance Cloud SQL
terraform output          # URLs, enregistrements DNS, noms des secrets
```

Ensuite, tout passe par la pipeline `terraform.yml` du repo : `plan`
automatique sur les pull requests, `apply` manuel (`workflow_dispatch`).

## Conventions importantes

- **Terraform ne gère pas les versions d'images.** Le champ `image` des services
  Cloud Run est en `ignore_changes` : la promotion d'une image est le rôle de la
  pipeline de déploiement. Sans cela, chaque `apply` ferait régresser la
  production vers le tag écrit dans le code.
- **Les valeurs de secrets ne sont pas dans git.** Les mots de passe de base de
  données et l'admin Keycloak sont générés par Terraform et déposés dans Secret
  Manager. Les identifiants SSO Google/Discord sont créés vides et alimentés à
  la main :
  ```bash
  printf '%s' "<client-id>" | gcloud secrets versions add pa-prod-google-client-id --data-file=-
  ```
- **L'état vit dans un bucket GCS versionné** (20 versions conservées) : un
  `apply` malheureux reste rattrapable.
- **Le bootstrap garde un état local** (`bootstrap/terraform.tfstate`), exclu de
  git : il crée le bucket qui héberge l'état des autres environnements.

## Coût mensuel attendu (hors crédits)

| Ressource | Coût |
|---|---|
| Cloud SQL `db-f1-micro` + 10 Go HDD | ~8 $ |
| Cloud Run Keycloak (`min-instances=1`) | ~7 $ |
| Cloud Run worker (`min-instances=1`, CPU allouée) | ~8 $ |
| Frontend, backend (scale-to-zero) | ~0 $ (offre gratuite) |
| Pub/Sub, Artifact Registry, Secret Manager, domain mappings | ~0 $ |

Les crédits GCP couvrent les 90 premiers jours. Pour revenir à ~0 $ ensuite :
passer Keycloak et le worker à `min_instances = 0` (le worker doit alors migrer
vers un abonnement push) — voir `docs/DEPLOY.md`, section « après les crédits ».
