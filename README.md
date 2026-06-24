# PA Tournament — Infra

Infrastructure du projet (spec : [`docs/PA-Tournament-Specs.md`](docs/PA-Tournament-Specs.md)).

## Architecture

```
React SPA ──► Backend Kotlin/Spring (API REST, brackets, matchs)
   │                │
   │ OIDC           │ SQL                table jobs (polling)
   ▼                ▼                        ▼
Keycloak        PostgreSQL ◄──────────── Worker Rust (import/export Excel)
```

## Contenu

| Fichier | Rôle |
|---|---|
| `Makefile` | Orchestration : `make dev` (tout en local), `make full` (tout en Docker), `make stop`… |
| `docker-compose.yml` | Stack locale : PostgreSQL + Keycloak (+ backend, worker, frontend avec `--profile full`) |
| `db/schema.sql` | Schéma PostgreSQL conforme à la spec §6 (cible de migration) |
| `keycloak/realm-pa-tournament.json` | Realm OIDC : clients `pa-frontend` (public, PKCE) et `pa-backend`, rôles player/organizer/admin |
| `docker/backend.Dockerfile` | Image du backend Kotlin/Spring |
| `docker/worker.Dockerfile` | Image du worker Rust |
| `docs/cloud-run.md` | Déploiement GCP / Cloud Run |

## Démarrage local

Prérequis : les repos `backend/`, `worker/`, `frontend/`, `infra/` clonés
côte à côte.

```bash
make dev    # db + keycloak (Docker) puis backend, worker et frontend en local
            #   Frontend  → http://localhost:5173
            #   Backend   → http://localhost:8080
            #   Keycloak  → http://localhost:8081 (admin/admin)
            #   Ctrl+C arrête les trois services, `make stop` coupe les conteneurs

make full   # stack 100% Docker (frontend → http://localhost:3000)
make help   # liste des commandes
```

Un Makefile délégateur à la racine de `PA4/` permet aussi de lancer
`make dev` depuis le dossier parent. Équivalent sans make :

```bash
cp .env.example .env
docker compose up -d                    # db + keycloak seulement
docker compose --profile full up -d --build   # stack complète
```

> Note : le backend possède aussi son propre `docker-compose.dev.yml` avec un
> schéma prototype (`db.sql`). Le schéma de référence à terme est
> `db/schema.sql` (conforme à la spec) — à migrer côté backend via Liquibase.
