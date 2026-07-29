# ADR-0002 — Communication backend ↔ worker par Pub/Sub

- **Date** : 2026-07-28
- **Statut** : accepté — remplace la décision §6.1.1 de la spécification
- **Portée** : infra, backend, worker

## Contexte

La spécification initiale (§6.1.1 et §7) prévoyait que le worker **polle la table
`jobs`** en base pour découvrir le travail à faire. Cela imposait au worker un
accès à la base du backend, ce que le brief interdit, et une requête inutile
toutes les 500 ms.

## Décision

Faire communiquer backend et worker par **deux topics Pub/Sub** :
`pa-prod-demandes` (backend → worker, consommé en *pull*) et `pa-prod-reponses`
(worker → backend, livré en *push* authentifié par jeton OIDC).

La table `jobs` est conservée, mais **uniquement pour le suivi d'état** (statut,
message d'erreur, résultat) : ce que la file ne sait pas faire.

## Conséquences

- le worker n'a plus **aucun** accès à la base : isolation conforme au brief
- file de rebut et politique de reprise fournies par le service managé
- le backend n'a rien à interroger : Pub/Sub le réveille
- le contrat de messages devient un contrat public entre deux langages, à
  verrouiller par des tests (voir ADR-0003 du repo `backend`)
- la spécification fonctionnelle §6.1.1 et §7 a été corrigée en conséquence
