# Intégration et livraison continues

Deux pipelines par repo applicatif, plus une pipeline d'infrastructure dans
`infra`. Tout est dans GitHub Actions.

```
        pull request                 push sur main              déclenchement manuel
             │                            │                             │
             ▼                            ▼                             ▼
    ┌─────────────────┐        ┌─────────────────────┐        ┌────────────────────┐
    │ ci.yml          │        │ ci.yml              │        │ deploy-prod.yml    │
    │ lint → tests    │        │ lint → tests →      │        │ vérifie l'image →  │
    │ (merge bloqué   │        │ build → push        │        │ déploie → smoke    │
    │  si rouge)      │        │ Docker Hub + AR     │        │ test → rollback si │
    └─────────────────┘        └─────────────────────┘        │ échec              │
                                                              └────────────────────┘
```

## Pipeline d'intégration (`ci.yml`)

Déclencheurs : `push` sur `main`, toute `pull_request`, et `workflow_dispatch`.

| Étape | frontend | backend | worker | infra |
|---|---|---|---|---|
| Linter | ESLint 9 | ktlint | `cargo fmt --check` + `clippy -D warnings` | `terraform fmt` + `validate`, shellcheck |
| Tests unitaires | Vitest (+ couverture) | JUnit 5 / MockK | `cargo test` | validation du realm JSON et de `docker-compose` |
| Vérification de types | `tsc -b` | (compilation Kotlin) | (compilation Rust) | — |
| Build | image Docker | image Docker | image Docker | image Keycloak |
| Publication | Docker Hub + Artifact Registry | idem | idem | idem |

Le job `image` est conditionné par `if: github.event_name != 'pull_request'` :
une PR valide la qualité sans publier d'image.

### Stratégie de tags

| Tag | Rôle |
|---|---|
| `sha-<court>` | **immuable**, c'est ce tag que l'on déploie et qui permet de rejouer un déploiement à l'identique |
| `main` | dernier état de la branche par défaut |
| `latest` | commodité (démarrage local, premier `terraform apply`) — jamais utilisé pour une promotion en production |

Déployer `latest` interdirait de savoir ce qui tourne réellement : le workflow de
déploiement prend donc un tag explicite en paramètre.

### Caches

- `actions/setup-node` (cache npm), `gradle/actions/setup-gradle`,
  `Swatinem/rust-cache` pour les dépendances ;
- `cache-from/to: type=gha` pour les couches Docker : combiné à l'ordre des
  `COPY` dans les Dockerfiles, un commit qui ne touche pas aux dépendances
  reconstruit uniquement la couche applicative.

## Pourquoi deux registres

- **Docker Hub** (public) : c'est le livrable visible, celui que demande la
  consigne. N'importe qui peut faire `docker pull <login>/pa-backend:sha-…`.
- **Artifact Registry** (`europe-west1`) : source utilisée par Cloud Run. Google
  recommande AR pour les déploiements (même région que les services, pas de
  limite de débit d'extraction, IAM du projet). Déployer directement depuis
  Docker Hub est possible mais exposé aux quotas d'extraction et à une
  disponibilité hors de notre contrôle.

Le coût est marginal : un seul `docker build`, deux destinations de push.

## Authentification vers GCP : aucune clé stockée

Les pipelines s'authentifient par **Workload Identity Federation** : GitHub
présente un jeton OIDC signé, GCP le vérifie et délivre un jeton d'accès de
courte durée.

```yaml
permissions:
  id-token: write          # autorise la demande du jeton OIDC
- uses: google-github-actions/auth@v3
  with:
    workload_identity_provider: ${{ vars.WIF_PROVIDER }}
    service_account: ${{ vars.WIF_SA_CI }}
```

Le provider n'accepte que les jetons dont
`assertion.repository_owner == 'PA-4AL'`, et chaque compte de service ne peut
être emprunté que par les repos listés dans le bootstrap. Conséquence : **aucune
clé JSON de compte de service n'existe**, donc rien à révoquer ni à faire tourner.

Séparation des privilèges :

| Compte de service | Utilisé par | Droits |
|---|---|---|
| `gh-ci-build` | job `image` des 4 repos | écriture sur Artifact Registry, rien d'autre |
| `gh-deploy` | `deploy-prod.yml` | `run.developer` + lecture du registre |
| `tf-admin` | `terraform.yml` (repo infra) | administration des ressources du projet |
| `pa-prod-run` | exécution des services Cloud Run | accès aux secrets et à Pub/Sub nécessaires |

## Pipeline de déploiement (`deploy-prod.yml`)

Manuelle (`workflow_dispatch`) avec un paramètre `image_tag`, rattachée à
l'environnement GitHub `production` (possibilité d'exiger une validation).

Séquence : vérifie que l'image existe → mémorise la révision en trafic →
`gcloud run deploy --image` → smoke test → en cas d'échec, affiche la commande
de retour arrière et sort en erreur.

**Seule l'image est modifiée.** Variables, secrets, réseau, scaling, sondes :
tout cela reste décrit par Terraform. C'est pour cela que le champ `image` des
services est en `ignore_changes` dans l'IAC — sans quoi le prochain
`terraform apply` ferait régresser la production vers le tag écrit dans le code.

Sondes utilisées par le smoke test :

| Service | Sonde |
|---|---|
| frontend | `GET /health` (nginx) |
| backend | `GET /actuator/health` |
| keycloak | `GET /realms/pa-tournament/.well-known/openid-configuration` |
| worker | condition `Ready` de la révision (pas d'ingress public) |

## Pipeline d'infrastructure (`terraform.yml`, repo infra)

- Sur PR touchant `terraform/**` : `terraform plan` publié en commentaire — on
  voit l'impact avant de fusionner.
- Manuellement : `plan` ou `apply`, sur `prod` ou `dev`.

L'IAC est volontairement séparée du déploiement applicatif : un correctif de
code ne doit jamais pouvoir toucher au réseau ou à la base de données.

## Variables et secrets attendus

Variables de repo (non sensibles) : `GCP_PROJECT_ID`, `GCP_REGION`,
`WIF_PROVIDER`, `WIF_SA_CI`, `WIF_SA_DEPLOY`, et `WIF_SA_TERRAFORM` pour `infra`.

Secrets de repo : `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.

Commandes de mise en place : voir [`DEPLOY.md`](DEPLOY.md#étape-4--variables-et-secrets-github).

## Limites assumées

- **Pas de tests d'intégration** : le backend n'a que des tests unitaires (les
  dépôts jOOQ sont mockés). Le test de chargement du contexte Spring a été retiré
  car il exigeait une base de données en CI. Piste : Testcontainers PostgreSQL.
- **Pas de tests end-to-end** sur le frontend (Playwright serait la suite
  logique) ; la couverture Vitest porte sur la configuration runtime et les
  helpers d'affichage.
- **Pas d'analyse de vulnérabilités des images** (Trivy en `continue-on-error`
  serait un ajout de quelques lignes).
- **Déploiement service par service** : pas d'orchestration inter-repos. Pour
  une montée de version globale, suivre l'ordre keycloak → backend → worker →
  frontend.
