# ADR-0001 — Héberger sur Cloud Run plutôt que Kubernetes

- **Date** : 2026-07-28
- **Statut** : accepté
- **Portée** : infra

## Contexte

Quatre conteneurs sans état à héberger (frontend, backend, worker, Keycloak),
un trafic de démonstration, et un budget de l'ordre de 10 € pour la durée du
projet. Le brief déconseille explicitement Kubernetes pour raisons de coût.

## Décision

Déployer sur **Cloud Run**, en `europe-west1`.

Écartés : **GKE** (un plan de contrôle et au moins un nœud facturés en
permanence, pour un besoin sans état) ; **Compute Engine** (il faudrait gérer
soi-même TLS, reverse proxy, mises à jour système) ; **App Engine** (moins
souple sur les images et le réseau).

## Conséquences

- facturation à l'usage, scale-to-zero possible sur le frontend et le backend
- HTTPS et certificats gérés et renouvelés gratuitement par Google
- toute charge de travail doit écouter sur `$PORT`, y compris un consommateur de
  file — d'où la sonde HTTP du worker (voir l'ADR-0005 du repo `worker`)
- un service scale-to-zero paie un démarrage à froid au premier appel (~15 s pour
  la JVM du backend)
