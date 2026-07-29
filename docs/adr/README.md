# Décisions d'architecture (ADR)

Un ADR consigne **une** décision structurante : son contexte, ce qui a été
décidé, et ce que ça coûte. Il est daté, numéroté, et ne change plus — si la
décision évolue, on écrit un nouvel ADR qui remplace le précédent.

## Quand en écrire un

Trois situations l'exigent :

1. **un changement dans un modèle** (schéma, contrat de messages, contrat d'API) ;
2. **l'ajout d'une dépendance externe** (bibliothèque, service managé) ;
3. **un choix d'architecture** (découpage, protocole, hébergement).

En dehors de ces cas, c'est au jugement de chacun. Mieux vaut un ADR de dix
lignes qu'aucun ADR.

## Template

Copier `template.md`, numéroter à la suite, et rester bref : le but est que ce
soit assez rapide à écrire pour que l'équipe le fasse vraiment.

## Où vivent les ADR

Chaque décision est consignée **dans le repo qu'elle concerne** :

| Repo | Portée |
|---|---|
| `infra` | infrastructure, déploiement, chaîne CI/CD, décisions transverses |
| `backend` | API, persistance, contrats, gestion d'erreur |
| `worker` | traitements asynchrones, isolation, politique de retry |
| `frontend` | interface, configuration, authentification côté client |

## Index — infra

| N° | Décision | Date | Statut |
|---|---|---|---|
| [0001](0001-heberger-sur-cloud-run.md) | Héberger sur Cloud Run plutôt que Kubernetes | 2026-07-28 | accepté |
| [0002](0002-pubsub-plutot-que-polling.md) | Communication backend ↔ worker par Pub/Sub | 2026-07-28 | accepté |
| [0003](0003-cloud-sql-ip-privee.md) | Cloud SQL en IP privée, sans IP publique | 2026-07-28 | accepté |
| [0004](0004-deux-registres-images.md) | Publier les images sur deux registres | 2026-07-28 | accepté |
| [0005](0005-federation-identite-sans-cle.md) | Authentifier la CI par fédération d'identité | 2026-07-28 | accepté |
| [0006](0006-terraform-ne-gere-pas-les-images.md) | Terraform ne décide pas des versions d'images | 2026-07-28 | accepté |
| [0007](0007-github-flow.md) | GitHub Flow plutôt que GitFlow | 2026-07-28 | accepté |
| [0008](0008-bastion-plutot-que-ip-publique-bdd.md) | Bastion arrêté par défaut pour l'accès à la base | 2026-07-29 | accepté |
