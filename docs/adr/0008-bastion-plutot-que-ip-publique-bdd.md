# ADR-0008 — Bastion arrêté par défaut pour l'accès à la base

- **Date** : 2026-07-29
- **Statut** : accepté
- **Portée** : infra

## Contexte

La base n'a pas d'IP publique (ADR-0003), donc aucun client graphique
(WebStorm, DataGrip) ne peut l'atteindre depuis un poste de développement. Or
inspecter les données est un besoin réel pendant le développement.

## Décision

Créer une VM `e2-micro` dans le VPC, **à l'état arrêté**, servant de point
d'entrée SSH pour un tunnel vers l'IP privée de la base. Le port 22 n'est ouvert
qu'aux adresses explicitement listées, et une validation Terraform **refuse**
`0.0.0.0/0`. Aucun compte de service n'est attaché à la VM.

Écarté : **ajouter une IP publique à Cloud SQL** — plus simple, mais cela
affaiblirait durablement la posture de sécurité de l'infrastructure pour un
besoin d'outillage ponctuel.

## Conséquences

- la base reste inaccessible depuis Internet
- coût quasi nul tant que la VM est arrêtée (~0,40 €/mois de disque)
- l'accès est explicite et traçable : il faut démarrer la VM
- deux frictions assumées : l'IP publique de la VM change à chaque démarrage, et
  la règle de pare-feu doit suivre l'adresse du poste si elle change
