# ADR-0003 — Cloud SQL en IP privée, sans IP publique

- **Date** : 2026-07-28
- **Statut** : accepté
- **Portée** : infra

## Contexte

Deux services doivent joindre PostgreSQL : le backend (Spring/JDBC) et Keycloak
(JDBC également). Les adresses de sortie de Cloud Run ne sont pas fixes, ce qui
rend inutilisable la liste de réseaux autorisés de Cloud SQL.

## Décision

Créer l'instance **sans IP publique**, dans un VPC dédié, et l'atteindre depuis
Cloud Run par **Direct VPC egress** (`PRIVATE_RANGES_ONLY`).

Écartés : **IP publique + réseaux autorisés** (il faudrait autoriser
`0.0.0.0/0`) ; **connecteur d'accès VPC serverless** (~8 $/mois pour le même
résultat) ; **connecteur Cloud SQL par socket Unix** (impose une bibliothèque de
*socket factory* côté JDBC, à intégrer deux fois — dans Spring **et** dans
Keycloak).

## Conséquences

- la base n'est **joignable que depuis le VPC** : un identifiant fuité ne suffit
  pas à y accéder
- une URL JDBC standard des deux côtés, aucune bibliothèque supplémentaire
- aucun surcoût réseau
- accéder à la base depuis un poste de développement demande un détour
  (voir ADR-0008)
