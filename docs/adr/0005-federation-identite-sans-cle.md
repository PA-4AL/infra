# ADR-0005 — Authentifier la CI par fédération d'identité, sans clé

- **Date** : 2026-07-28
- **Statut** : accepté
- **Portée** : infra

## Contexte

Les pipelines GitHub Actions doivent pousser des images, déployer des révisions
Cloud Run et appliquer du Terraform. La méthode la plus répandue — une clé JSON
de compte de service stockée en secret GitHub — crée un secret permanent,
exfiltrable, et qu'il faut faire tourner à la main.

## Décision

Utiliser **Workload Identity Federation** : GitHub présente un jeton OIDC signé,
GCP le vérifie et délivre un jeton d'accès de courte durée. Le fournisseur
n'accepte que les jetons dont `assertion.repository_owner == 'PA-4AL'`, et chaque
compte de service ne peut être emprunté que par les repos déclarés.

Trois comptes distincts, au moindre privilège : `gh-ci-build` (écriture sur le
registre uniquement), `gh-deploy` (déploiement Cloud Run), `tf-admin` (Terraform).

## Conséquences

- **aucune clé de compte de service n'existe** : rien à révoquer ni à faire tourner
- un repo compromis ne peut emprunter que les comptes qui lui sont accordés
- la mise en place est plus longue qu'un simple secret, et le bootstrap doit être
  appliqué en local (problème de l'œuf et de la poule)
- effet de bord constaté : le moindre privilège fait échouer toute étape de
  pipeline qui déborde de son périmètre — c'est le comportement voulu
