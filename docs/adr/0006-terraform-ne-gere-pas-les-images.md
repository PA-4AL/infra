# ADR-0006 — Terraform ne décide pas des versions d'images

- **Date** : 2026-07-28
- **Statut** : accepté
- **Portée** : infra

## Contexte

Le champ `image` d'un service Cloud Run fait partie de sa définition Terraform.
Si l'IAC en est propriétaire, chaque `terraform apply` réaligne la production sur
le tag écrit dans le code — donc annule le dernier déploiement.

## Décision

Mettre `template[0].containers[0].image` en **`ignore_changes`**. Terraform décrit
l'infrastructure (réseau, base, files, services, IAM, domaines) ; la **pipeline de
déploiement** décide de la version déployée, via `gcloud run deploy`.

## Conséquences

- les deux responsabilités ne se marchent plus dessus
- `terraform plan` reste propre après un déploiement (« no changes »)
- l'IAC ne documente plus quelle version tourne : la source de vérité devient
  Cloud Run, à interroger (`gcloud run services describe`)
- le tag écrit dans le code ne sert qu'à la **création initiale** du service
