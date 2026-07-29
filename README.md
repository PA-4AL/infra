# PA Tournament — Infra

[![CI](https://github.com/PA-4AL/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/PA-4AL/infra/actions/workflows/ci.yml)
[![Terraform](https://github.com/PA-4AL/infra/actions/workflows/terraform.yml/badge.svg)](https://github.com/PA-4AL/infra/actions/workflows/terraform.yml)

Infrastructure, IAC et documentation d'exploitation du projet
(spec fonctionnelle : [`docs/PA-Tournament-Specs.md`](docs/PA-Tournament-Specs.md)).

## Architecture

```
React SPA ──► Backend Kotlin/Spring (API REST, brackets, matchs)
   │                │
   │ OIDC           │ SQL           Pub/Sub : topic-demandes (pull)
   ▼                ▼                        topic-reponses (push OIDC)
Keycloak        PostgreSQL                        ▼
                                    Worker Rust (import/export Excel)
```

En production, ces quatre composants tournent sur Cloud Run derrière un domaine
en HTTPS, avec une base Cloud SQL en IP privée :

| | |
|---|---|
| Application | <https://app.patournament.fr> |
| API | <https://api.patournament.fr> |
| Identité | <https://auth.patournament.fr> |

Choix techniques : [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) ·
exploitation au quotidien : [`docs/EXPLOITATION.md`](docs/EXPLOITATION.md).

## Documentation

| Document | Contenu |
|---|---|
| [`docs/EXPLOITATION.md`](docs/EXPLOITATION.md) | **Ce qui tourne en production**, rôle de chaque service et manipulations courantes |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | **Runbook de mise en production**, de zéro au domaine en HTTPS |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Architecture cible et justification des choix |
| [`docs/GIT-FLOW.md`](docs/GIT-FLOW.md) | Flow de développement (GitHub Flow), commits, PR, protections |
| [`docs/CI-CD.md`](docs/CI-CD.md) | Pipelines d'intégration, de déploiement et d'infrastructure |
| [`docs/DOCKER.md`](docs/DOCKER.md) | Choix des images, tags, optimisations, exécution non privilégiée |
| [`terraform/README.md`](terraform/README.md) | IAC : arborescence, environnements, commandes |

## Contenu du repo

| Fichier | Rôle |
|---|---|
| `terraform/` | Toutes les ressources cloud (bootstrap, modules, environnements dev/prod) |
| `Makefile` | Orchestration locale : `make dev`, `make full`, `make stop`… |
| `docker-compose.yml` | Stack locale : PostgreSQL + Keycloak (+ les 3 services avec `--profile full`) |
| `db/schema.sql` | Schéma PostgreSQL conforme à la spec §6 (référence ; en prod, Liquibase côté backend) |
| `keycloak/realm-pa-tournament.json` | Realm OIDC : clients `pa-frontend` (public, PKCE) et `pa-backend`, rôles player/organizer/admin |
| `keycloak/themes/pa/` | Thème de la page de connexion |
| `docker/keycloak.Dockerfile` | Image Keycloak « optimisée » (realm + thème embarqués) |
| `scripts/keycloak-configure.sh` | Configuration post-déploiement du realm (URIs de prod, SSO) — idempotent |

> Les Dockerfiles du backend, du worker et du frontend vivent **dans leurs
> repos respectifs** : chaque pipeline construit son image sans dépendre d'un
> autre dépôt.

## Démarrage local

Prérequis : les repos `backend/`, `worker/`, `frontend/`, `infra/` clonés côte à côte.

```bash
make dev    # db + keycloak (Docker) puis backend, worker et frontend en local
            #   Frontend  → http://localhost:5173
            #   Backend   → http://localhost:8080
            #   Keycloak  → http://localhost:8081 (admin/admin)
            #   Ctrl+C arrête les trois services, `make stop` coupe les conteneurs

make full   # stack 100% Docker (frontend → http://localhost:3000)
make help   # liste des commandes
```

Équivalent sans make :

```bash
cp .env.example .env
docker compose up -d                          # db + keycloak seulement
docker compose --profile full up -d --build   # stack complète
```

Deux points à connaître en local :

- **SSO Google/Discord** : l'import du realm ne substitue pas les variables
  d'environnement. Après le démarrage, appliquer la configuration :
  ```bash
  KEYCLOAK_URL=http://localhost:8081 KC_ADMIN=admin KC_ADMIN_PASSWORD=admin \
  APP_ORIGIN=http://localhost:5173 \
  GOOGLE_CLIENT_ID=… GOOGLE_CLIENT_SECRET=… ./scripts/keycloak-configure.sh
  ```
- **Worker** : il consomme Pub/Sub (pas la base). Sans abonnement réel ni
  émulateur (`PUBSUB_EMULATOR_HOST`), le conteneur s'arrête avec un message
  d'authentification explicite — c'est attendu.

> Note : le backend possède aussi son propre `docker-compose.dev.yml` avec un
> schéma prototype (`db.sql`). Le schéma de référence est `db/schema.sql`,
> appliqué en production par Liquibase au démarrage du backend.
