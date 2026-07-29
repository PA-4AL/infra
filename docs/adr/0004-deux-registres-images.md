# ADR-0004 — Publier les images sur deux registres

- **Date** : 2026-07-28
- **Statut** : accepté
- **Portée** : infra

## Contexte

Le brief demande que les livrables conteneurisés soient **publiés sur un
registre**, et cite Docker Hub en exemple. Par ailleurs, Google recommande
Artifact Registry comme source des déploiements Cloud Run.

## Décision

Pousser chaque image sur **les deux** : Docker Hub (public, c'est le livrable
consultable) et Artifact Registry (régional, source utilisée par Cloud Run).

Écartés : **Artifact Registry seul** (le livrable ne serait pas consultable sans
accès au projet GCP) ; **Docker Hub seul** (Cloud Run peut le faire, mais on
dépend alors des quotas d'extraction et d'une disponibilité hors de notre
contrôle).

## Conséquences

- un seul `docker build`, deux destinations de push : le coût est marginal
- deux jeux d'identifiants à gérer dans la CI (fédération d'identité pour GCP,
  jeton d'accès pour Docker Hub)
- les tags doivent rester identiques d'un registre à l'autre pour éviter toute
  ambiguïté sur ce qui est déployé
