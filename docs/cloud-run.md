# Déploiement GCP / Cloud Run

La spec (§2) cible un hébergement conteneurisé serverless sur Cloud Run.
Découpage en 4 services + dépendances managées :

| Service Cloud Run | Image | Notes |
|---|---|---|
| `pa-frontend` | `frontend/Dockerfile` | nginx statique, écoute :8080 |
| `pa-backend` | `infra/docker/backend.Dockerfile` | Spring Boot, scale 0→N |
| `pa-worker` | `infra/docker/worker.Dockerfile` | polle la table `jobs` — min-instances=1 |
| Keycloak | image `quay.io/keycloak/keycloak` | ou Cloud Run + Cloud SQL dédiée |

Dépendances :

- **Cloud SQL (PostgreSQL)** — schéma `infra/db/schema.sql`. Connexion des
  services via le connecteur Cloud SQL (`--add-cloudsql-instances`).
- **Cloud Storage** — bucket pour les fichiers Excel d'import/export
  (`jobs.file_url`).
- **Artifact Registry** — stockage des images.

## Build & push des images

```bash
PROJECT=mon-projet REGION=europe-west1
REPO=$REGION-docker.pkg.dev/$PROJECT/pa

gcloud artifacts repositories create pa --repository-format=docker --location=$REGION

# Frontend (les variables VITE_* sont figées au build)
docker build ../frontend -t $REPO/frontend:latest \
  --build-arg VITE_API_URL=https://pa-backend-xxxx.run.app \
  --build-arg VITE_KEYCLOAK_URL=https://keycloak-xxxx.run.app

# Backend / Worker
docker build ../backend -f docker/backend.Dockerfile -t $REPO/backend:latest
docker build ../worker  -f docker/worker.Dockerfile  -t $REPO/worker:latest

docker push $REPO/frontend:latest $REPO/backend:latest $REPO/worker:latest
```

## Déploiement

```bash
gcloud run deploy pa-frontend --image $REPO/frontend:latest --region $REGION --allow-unauthenticated
gcloud run deploy pa-backend  --image $REPO/backend:latest  --region $REGION --allow-unauthenticated \
  --add-cloudsql-instances $PROJECT:$REGION:pa-db \
  --set-env-vars SPRING_DATASOURCE_URL=...,KEYCLOAK_ISSUER_URI=...
gcloud run deploy pa-worker   --image $REPO/worker:latest   --region $REGION --no-allow-unauthenticated \
  --min-instances 1 \
  --add-cloudsql-instances $PROJECT:$REGION:pa-db \
  --set-env-vars DATABASE_URL=...
```

> Le worker polle la BDD (décision spec §6.1.1) : il lui faut
> `--min-instances 1` (pas de scale-to-zero), ou une migration vers Pub/Sub
> si on veut du vrai serverless.
