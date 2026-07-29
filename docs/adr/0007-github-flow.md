# ADR-0007 — GitHub Flow plutôt que GitFlow

- **Date** : 2026-07-28
- **Statut** : accepté
- **Portée** : infra (transverse aux 4 repos)

## Contexte

Le projet est réparti sur quatre repos qui doivent avancer ensemble, à trois
contributeurs, sans versions supportées en parallèle. Le brief demande un flow
documenté **et respecté**, et une pipeline qui part à chaque commit sur `main`.

## Décision

**GitHub Flow** : une seule branche longue (`main`, toujours déployable), des
branches de fonctionnalité courtes, une pull request avec CI verte obligatoire,
fusion en *squash*.

Écarté : **GitFlow** — maintenir `develop`, `release/*` et `hotfix/*` sur quatre
repos quadruplerait la cérémonie sans bénéfice, faute de versions à supporter
simultanément.

## Conséquences

- une pipeline se déclenche naturellement à chaque commit sur `main`
- l'historique reste lisible : un commit par PR
- `main` doit rester déployable en permanence — c'est la contrainte à tenir
- les repos ont dû passer **en public** : les règles de protection de branche ne
  sont pas disponibles sur les repos privés d'une organisation gratuite. D'où
  l'obligation de n'avoir aucun secret dans l'historique
