# Mise en production — procédure complète

Runbook à suivre dans l'ordre, de zéro jusqu'à `https://app.<domaine>` en ligne.
Chaque étape indique **qui l'exécute**, **combien de temps** elle prend et
**comment vérifier** qu'elle a réussi.

Architecture cible et choix techniques : voir [`ARCHITECTURE.md`](ARCHITECTURE.md).
Détail des pipelines : [`CI-CD.md`](CI-CD.md). Images : [`DOCKER.md`](DOCKER.md).

---

## Vue d'ensemble

```
0. Comptes (GCP, Docker Hub, domaine)          ~30 min   manuel
1. Outillage local (gcloud, terraform)          ~5 min   manuel
2. Projet GCP + facturation                    ~10 min   manuel
3. Bootstrap Terraform (WIF, registre, état)   ~10 min   terraform (local)
4. Variables et secrets GitHub                 ~10 min   gh CLI
5. Première publication des 4 images           ~15 min   pipelines CI
6. Provisionnement de l'environnement prod     ~20 min   pipeline Terraform
7. Configuration Keycloak (SSO, URIs)           ~5 min   script
8. Domaine + HTTPS                             ~20 min + propagation
9. Recette                                     ~15 min   manuel
```

Total : environ 2 h 30 de travail effectif, hors propagation DNS et
délivrance du certificat (jusqu'à 24 h dans le pire cas, en général 15 min).

---

## Étape 0 — Comptes et prérequis

| Quoi | Où | Notes |
|---|---|---|
| Compte Google Cloud | <https://console.cloud.google.com> | Les 300 $ de crédits d'essai couvrent 90 jours. Une carte bancaire est demandée mais rien n'est débité sans passage explicite en compte payant. |
| Compte Docker Hub | <https://hub.docker.com> | Créer un **Access Token** (Account settings → Personal access tokens), permissions *Read & Write*. Ne jamais utiliser le mot de passe du compte. |
| Nom de domaine | <https://dash.cloudflare.com> (Registrar) | ~10 €/an en `.com`, moins en `.dev`/`.fr`. Garder le DNS chez Cloudflare. |

> Le compte Docker Hub sert à publier les livrables (critère « conteneurs mis en
> ligne sur un registre »). Artifact Registry reste la source utilisée par
> Cloud Run — voir [`CI-CD.md`](CI-CD.md#pourquoi-deux-registres).

## Étape 1 — Outillage local

```bash
# Terraform (déjà installé dans ~/.local/bin sur le poste de dev)
terraform version     # attendu : v1.15.x

# gcloud
gcloud version        # attendu : Google Cloud SDK 5xx

# GitHub CLI, authentifié sur le compte propriétaire de l'organisation PA-4AL
gh auth status
```

Si Terraform manque :

```bash
TFV=1.15.8
curl -fsSL -o /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TFV}/terraform_${TFV}_linux_amd64.zip"
unzip -o /tmp/tf.zip -d ~/.local/bin && terraform version
```

## Étape 2 — Projet GCP et facturation

```bash
gcloud auth login                      # compte Google
gcloud auth application-default login  # identifiants utilisés par Terraform

# Créer le projet (l'identifiant doit être unique au monde)
export PROJECT_ID=pa-tournament-prod   # à adapter si déjà pris
gcloud projects create "$PROJECT_ID" --name="PA Tournament"
gcloud config set project "$PROJECT_ID"

# Rattacher la facturation (indispensable : Cloud Run et Cloud SQL la réclament)
gcloud billing accounts list                       # relever ACCOUNT_ID
gcloud billing projects link "$PROJECT_ID" --billing-account=<ACCOUNT_ID>
```

**Garde-fou budget** (fortement conseillé) : Console → Billing → Budgets &
alerts → budget de 20 € avec alertes à 50 / 90 / 100 %.

**Vérification** : `gcloud billing projects describe "$PROJECT_ID"` affiche
`billingEnabled: true`.

## Étape 3 — Bootstrap Terraform

Crée ce dont les pipelines ont besoin : APIs activées, bucket d'état, Artifact
Registry, fédération d'identité GitHub et comptes de service.

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply -var project_id="$PROJECT_ID"      # ~8 min (activation des APIs)
terraform output                                   # ⚠️ garder cette sortie
```

Sortie attendue (exemple) :

```
artifact_registry          = "europe-west1-docker.pkg.dev/pa-tournament-prod/pa"
sa_ci_email                = "gh-ci-build@pa-tournament-prod.iam.gserviceaccount.com"
sa_deploy_email            = "gh-deploy@pa-tournament-prod.iam.gserviceaccount.com"
sa_terraform_email         = "tf-admin@pa-tournament-prod.iam.gserviceaccount.com"
tfstate_bucket             = "pa-tournament-prod-tfstate"
workload_identity_provider = "projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
```

**Aucune clé de compte de service n'est créée** : GitHub s'authentifie par jeton
OIDC (Workload Identity Federation). C'est le point le plus important de la
sécurité de la chaîne — une clé JSON dans un secret GitHub serait un secret
permanent exfiltrable.

**Vérification** : `gcloud artifacts repositories list --location=europe-west1`
liste le dépôt `pa`.

## Étape 4 — Variables et secrets GitHub

**Version courte** — un script fait les variables, l'environnement `production`
et les règles de protection de `main` pour les 4 repos :

```bash
cd infra
PROJECT_ID="$PROJECT_ID" ./scripts/github-setup.sh
# puis, une fois par repo (saisie interactive, rien n'est écrit sur disque) :
for repo in infra backend worker frontend; do
  gh secret set DOCKERHUB_USERNAME --repo "PA-4AL/$repo"
  gh secret set DOCKERHUB_TOKEN    --repo "PA-4AL/$repo"
done
```

**Version détaillée** (ce que fait le script). Depuis la racine `PA4/` :

```bash
cd infra/terraform/bootstrap
export WIF_PROVIDER=$(terraform output -raw workload_identity_provider)
export WIF_SA_CI=$(terraform output -raw sa_ci_email)
export WIF_SA_DEPLOY=$(terraform output -raw sa_deploy_email)
export WIF_SA_TERRAFORM=$(terraform output -raw sa_terraform_email)
cd ../../..

for repo in infra backend worker frontend; do
  gh variable set GCP_PROJECT_ID  --repo "PA-4AL/$repo" --body "$PROJECT_ID"
  gh variable set GCP_REGION      --repo "PA-4AL/$repo" --body "europe-west1"
  gh variable set WIF_PROVIDER    --repo "PA-4AL/$repo" --body "$WIF_PROVIDER"
  gh variable set WIF_SA_CI       --repo "PA-4AL/$repo" --body "$WIF_SA_CI"
  gh variable set WIF_SA_DEPLOY   --repo "PA-4AL/$repo" --body "$WIF_SA_DEPLOY"
done
gh variable set WIF_SA_TERRAFORM --repo PA-4AL/infra --body "$WIF_SA_TERRAFORM"
```

Secrets Docker Hub (saisie interactive, la valeur n'apparaît ni dans
l'historique du shell ni dans un fichier) :

```bash
for repo in infra backend worker frontend; do
  gh secret set DOCKERHUB_USERNAME --repo "PA-4AL/$repo"   # ton login Docker Hub
  gh secret set DOCKERHUB_TOKEN    --repo "PA-4AL/$repo"   # l'access token
done
```

Environnement de déploiement (permet d'exiger une validation manuelle avant
toute mise en production) :

```bash
for repo in infra backend worker frontend; do
  gh api -X PUT "repos/PA-4AL/$repo/environments/production" >/dev/null
done
```

**Vérification** : `gh variable list --repo PA-4AL/backend` affiche les 5
variables, `gh secret list --repo PA-4AL/backend` les 2 secrets.

## Étape 5 — Première publication des images

⚠️ **Ordre important** : Cloud Run refuse de créer un service dont l'image
n'existe pas. Les images doivent donc être publiées **avant** l'étape 6.

Pousser sur `main` dans les 4 repos (ordre habituel du projet :
infra → backend → worker → frontend), ou déclencher les pipelines à la main :

```bash
for repo in infra backend worker frontend; do
  gh workflow run ci.yml --repo "PA-4AL/$repo"
done
gh run list --repo PA-4AL/infra --limit 3
```

**Vérification** :

```bash
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/$PROJECT_ID/pa --include-tags
```

Les 4 images (`frontend`, `backend`, `worker`, `keycloak`) doivent apparaître
avec les tags `latest`, `main` et `sha-…`. Elles sont aussi visibles publiquement
sur `https://hub.docker.com/u/<ton-login>`.

## Étape 6 — Provisionnement de la production

Renseigner `infra/terraform/envs/prod/terraform.tfvars` :

```hcl
project_id               = "pa-tournament-prod"
region                   = "europe-west1"
deployer_service_account = "gh-deploy@pa-tournament-prod.iam.gserviceaccount.com"
# domain = "exemple.fr"        ← laisser commenté pour ce premier apply
# alert_email = "toi@exemple.fr"
```

Puis, en local pour le premier apply (ensuite tout passe par la pipeline) :

```bash
cd infra/terraform/envs/prod
terraform init -backend-config="bucket=${PROJECT_ID}-tfstate"
terraform plan      # relire : ~40 ressources à créer
terraform apply     # ~15 min (la création de l'instance Cloud SQL est le poste long)
terraform output
```

Ce que cela crée : VPC + accès privé, Cloud SQL PostgreSQL (bases `pa` et
`keycloak`, mots de passe générés et déposés dans Secret Manager), topics et
abonnements Pub/Sub avec file de rebut, 4 services Cloud Run, comptes de
service d'exécution, alerte 5xx.

**Vérifications** :

```bash
terraform output -json urls | python3 -m json.tool
curl -s "$(terraform output -json urls | python3 -c 'import json,sys;print(json.load(sys.stdin)["frontend"])')/healthz"
# → ok
```

### Seconde passe : les vraies URLs (obligatoire sans domaine)

Le backend a besoin de l'origine du frontend (CORS) et le frontend de celle du
backend (appels API) : Terraform refuserait ce cycle, les URLs ne peuvent donc
pas être lues depuis les ressources. Tant qu'aucun domaine n'est configuré, il
faut les reporter à la main après le premier apply — les URLs Cloud Run **ne sont
pas devinables** (certains projets utilisent l'ancien format
`service-xxxxxxxxxx-ew.a.run.app` au lieu de `service-NUMERO.region.run.app`).

```bash
terraform output -json urls        # relever frontend / backend / keycloak
```

Reporter les trois valeurs dans `terraform.tfvars` :

```hcl
app_origin_override  = "https://pa-prod-frontend-xxxxxxxxxx-ew.a.run.app"
api_origin_override  = "https://pa-prod-backend-xxxxxxxxxx-ew.a.run.app"
auth_origin_override = "https://pa-prod-keycloak-xxxxxxxxxx-ew.a.run.app"
```

puis `terraform apply` à nouveau : les services repartent avec les bonnes URLs
(config runtime du frontend, CORS et issuer du backend, hostname de Keycloak).

Cette étape **disparaît** dès que `domain` est renseigné (étape 8) : les origines
sont alors dérivées du domaine, sans aucune ambiguïté. Les overrides peuvent être
supprimés à ce moment-là.

> Si le backend reste en erreur, c'est presque toujours la base : vérifier que
> l'IP privée est bien injectée (`gcloud run services describe pa-prod-backend
> --region europe-west1 --format='value(spec.template.spec.containers[0].env)'`)
> et lire les logs Liquibase (`gcloud run services logs read pa-prod-backend
> --region europe-west1 --limit 100`).

## Étape 7 — Configuration Keycloak

Le realm (clients, rôles, thème) est importé automatiquement au premier
démarrage. Restent les valeurs propres à l'environnement : URIs de redirection
de production et identifiants SSO.

```bash
cd infra
export PROJECT_ID=<PROJECT_ID>

# 1) Déposer les identifiants SSO dans Secret Manager (jamais dans git)
printf '%s' "<google-client-id>"     | gcloud secrets versions add pa-prod-google-client-id     --data-file=-
printf '%s' "<google-client-secret>" | gcloud secrets versions add pa-prod-google-client-secret --data-file=-
printf '%s' "<discord-client-id>"     | gcloud secrets versions add pa-prod-discord-client-id     --data-file=-
printf '%s' "<discord-client-secret>" | gcloud secrets versions add pa-prod-discord-client-secret --data-file=-

# 2) Appliquer la configuration
export KEYCLOAK_URL=$(gcloud run services describe pa-prod-keycloak --region europe-west1 --format='value(status.url)')
export KC_ADMIN=admin
export KC_ADMIN_PASSWORD=$(gcloud secrets versions access latest --secret=pa-prod-keycloak-admin-password)
export APP_ORIGIN=$(gcloud run services describe pa-prod-frontend --region europe-west1 --format='value(status.url)')
export GOOGLE_CLIENT_ID=$(gcloud secrets versions access latest --secret=pa-prod-google-client-id)
export GOOGLE_CLIENT_SECRET=$(gcloud secrets versions access latest --secret=pa-prod-google-client-secret)
export DISCORD_CLIENT_ID=$(gcloud secrets versions access latest --secret=pa-prod-discord-client-id)
export DISCORD_CLIENT_SECRET=$(gcloud secrets versions access latest --secret=pa-prod-discord-client-secret)

./scripts/keycloak-configure.sh
```

Le script est **idempotent** : on peut le rejouer après chaque changement
d'URL (notamment après l'étape 8, avec `APP_ORIGIN=https://app.<domaine>`).

Il applique aussi un **durcissement indispensable**, parce que le realm versionné
contient des valeurs de développement et que les repos sont publics :

- désactivation des comptes de démonstration `demo` et `joueur` (leurs mots de
  passe sont lisibles dans `keycloak/realm-pa-tournament.json`, et `demo` a le
  rôle `organizer`) — passer `DISABLE_DEMO_USERS=false` pour les garder en local ;
- régénération du secret du client `pa-backend`, livré à `change-me-in-prod`.

> Sans cette étape, n'importe qui pourrait se connecter en organisateur sur la
> production avec les identifiants lus dans le dépôt.

Côté fournisseurs d'identité, déclarer les URIs de callback affichées par le
script :

- Google : <https://console.cloud.google.com/apis/credentials> → client OAuth
  « Application Web » → URI de redirection autorisée
  `https://auth.<domaine>/realms/pa-tournament/broker/google/endpoint`
- Discord : <https://discord.com/developers/applications> → OAuth2 → Redirect
  `https://auth.<domaine>/realms/pa-tournament/broker/discord/endpoint`

**Vérification** : la page de connexion affiche les boutons Google et Discord,
et un login aboutit.

## Étape 8 — Domaine et HTTPS

1. **Vérifier la propriété du domaine** (obligatoire pour Cloud Run) :
   <https://search.google.com/search-console> → « Préfixe de domaine » → ajouter
   le TXT fourni dans le DNS Cloudflare → valider.

2. **Déclarer le domaine dans l'IAC** — décommenter dans `terraform.tfvars` :

   ```hcl
   domain = "exemple.fr"
   ```

   puis :

   ```bash
   cd infra/terraform/envs/prod && terraform apply
   terraform output -json dns_records | python3 -m json.tool
   ```

3. **Créer les enregistrements DNS** dans Cloudflare, en respectant ce qui est
   affiché (en général 3 CNAME vers `ghs.googlehosted.com`) :

   | Nom | Type | Cible | Proxy |
   |---|---|---|---|
   | `app` | CNAME | `ghs.googlehosted.com` | **DNS only (nuage gris)** |
   | `api` | CNAME | `ghs.googlehosted.com` | **DNS only** |
   | `auth` | CNAME | `ghs.googlehosted.com` | **DNS only** |

   > Le proxy orange de Cloudflare **doit être désactivé** : sinon Google ne peut
   > pas valider le domaine et le certificat n'est jamais délivré.

4. **Attendre le certificat** (15 min en général) :

   ```bash
   gcloud beta run domain-mappings describe --domain app.exemple.fr \
     --region europe-west1 --format='value(status.conditions)'
   curl -sI https://app.exemple.fr | head -3
   ```

5. **Rejouer l'étape 7** avec `APP_ORIGIN=https://app.exemple.fr` pour que
   Keycloak accepte les redirections du domaine, et mettre à jour les URIs de
   callback Google/Discord.

## Étape 9 — Déployer une nouvelle version (au quotidien)

1. La CI publie une image à chaque commit sur `main` et affiche le tag
   `sha-xxxxxxx` dans son récapitulatif.
2. Lancer la mise en production, service par service :

```bash
gh workflow run deploy-prod.yml --repo PA-4AL/backend -f image_tag=sha-a1b2c3d
gh run watch --repo PA-4AL/backend
```

Le workflow vérifie que l'image existe, note la révision en place, déploie,
puis exécute un smoke test. En cas d'échec, il affiche la commande exacte de
retour arrière :

```bash
gcloud run services update-traffic pa-prod-backend \
  --region europe-west1 --to-revisions <REVISION_PRECEDENTE>=100
```

Ordre conseillé pour une montée de version globale :
**keycloak → backend → worker → frontend**.

## Étape 10 — Recette

- [ ] `terraform plan` sur `envs/prod` annonce **aucun changement**
- [ ] Une pull request déclenche lint + tests, et le merge est bloqué si ça casse
- [ ] Un commit sur `main` publie une image sur Docker Hub **et** Artifact Registry
- [ ] `deploy-prod.yml` déploie le tag choisi et le smoke test passe
- [ ] `https://app.<domaine>` répond en HTTPS avec un certificat valide
- [ ] Connexion par email/mot de passe, puis par Google, puis par Discord
- [ ] Création d'un tournoi, inscription, génération du bracket, saisie d'un score
- [ ] Import d'un `.xlsx` d'équipes, puis export de l'état du tournoi
- [ ] Retour arrière testé sur un service (`update-traffic`)
- [ ] Alerte budget active, coût du jour conforme

---

## Dépannage

| Symptôme | Cause probable | Correctif |
|---|---|---|
| `Permission denied` sur `terraform apply` en pipeline | La variable `WIF_SA_TERRAFORM` manque, ou le repo n'est pas autorisé dans le provider WIF | Vérifier `gh variable list --repo PA-4AL/infra` et la condition `assertion.repository_owner` du bootstrap |
| Cloud Run : « Image not found » | L'étape 5 n'a pas été faite avant l'étape 6 | Relancer la CI, puis `terraform apply` |
| `Invalid Tier (db-f1-micro) for (ENTERPRISE_PLUS) Edition` | L'API Cloud SQL a choisi l'édition Enterprise Plus, incompatible avec les gabarits à cœur partagé | Déjà corrigé dans le module (`edition = "ENTERPRISE"`). Si l'erreur revient, vérifier que ce champ n'a pas été retiré |
| `Value for undeclared variable` au `plan` | Une variable a été ajoutée à `terraform.tfvars` sans être déclarée dans `envs/<env>/main.tf` | Déclarer la variable et la câbler au module `platform` — sinon la valeur est **silencieusement ignorée** |
| Appels API bloqués par CORS, ou login qui boucle, sans domaine | Les URLs injectées ne correspondent pas aux URLs réelles | Faire la « seconde passe » ci-dessus (`*_origin_override`) |
| Cloud Run : « Container failed to listen on PORT » | Le conteneur ne démarre pas (worker sans identifiants Pub/Sub, backend sans base) | `gcloud run services logs read <service> --region europe-west1` |
| Backend en 401 sur tous les appels | `KEYCLOAK_ISSUER_URI` ne correspond pas à l'issuer réel du token | Vérifier que `KC_HOSTNAME` et l'URI d'issuer utilisent la même origine (domaine, pas run.app) |
| Erreur CORS dans le navigateur | `APP_CORS_ALLOWED_ORIGINS` ≠ origine réelle du frontend | Corriger `domain` dans les tfvars et réappliquer |
| Le login Keycloak boucle ou refuse la redirection | URIs de redirection non mises à jour | Rejouer `scripts/keycloak-configure.sh` avec le bon `APP_ORIGIN` |
| Certificat jamais délivré | Proxy Cloudflare actif, ou domaine non vérifié | Passer le CNAME en « DNS only », vérifier le domaine dans Search Console |
| Le worker ne consomme rien | Abonnement vide, ou révision non prête | `gcloud pubsub subscriptions pull pa-prod-worker-demandes --limit 5`, puis les logs du service |

## Après les 90 jours de crédits

Coût courant : **~23 $/mois** (Cloud SQL ~8 $, Keycloak `min-instances=1` ~7 $,
worker `min-instances=1` ~8 $). Pour revenir près de 0 € :

1. `keycloak_min_instances = 0` — cold start de ~25 s au premier login.
2. Migrer le worker vers un abonnement **push** (endpoint HTTP au lieu de la
   boucle pull) puis `worker_min_instances = 0` : il ne consomme alors du CPU
   que pendant un traitement, dans les limites de l'offre gratuite.
3. Remplacer Cloud SQL par un PostgreSQL managé gratuit (Neon, Supabase) : il
   suffit de changer `SPRING_DATASOURCE_URL` / `KC_DB_URL` et de retirer le
   module `database` de l'IAC.
4. `gcloud run services delete` sur l'environnement `dev` s'il a été déployé.
