# Flow de développement

Le projet suit un **GitHub Flow** (variante trunk-based) : une seule branche
longue par repo, `main`, et des branches de fonctionnalité courtes fusionnées
par pull request.

## Pourquoi ce flow et pas GitFlow

Le projet est réparti sur **4 repos** (`infra`, `backend`, `worker`, `frontend`)
qui doivent avancer ensemble. Maintenir `develop` + `release/*` + `hotfix/*` sur
chacun d'eux quadruplerait la cérémonie sans rien apporter : il n'y a pas de
versions supportées en parallèle, et le déploiement est continu par service.
GitHub Flow donne exactement ce que demande la consigne — une pipeline qui part
à chaque commit sur `main` — avec une seule règle à tenir : *`main` est toujours
déployable*.

```
main ─────●───────────●─────────────●──────────►  (toujours déployable, protégée)
           \         /               \
            ●───●───●  feat/…         ●───●  fix/…
            (PR + CI verte)           (PR + CI verte)
```

## Branches

| Type | Convention | Exemple | Durée de vie |
|---|---|---|---|
| Fonctionnalité | `feat/<sujet-court>` | `feat/bracket-double-elim` | quelques jours max |
| Correctif | `fix/<sujet-court>` | `fix/cors-preflight` | quelques heures |
| Technique / outillage | `chore/<sujet>` | `chore/bump-keycloak-26.7` | courte |
| Documentation | `docs/<sujet>` | `docs/runbook-deploiement` | courte |
| Correctif urgent en prod | `hotfix/<sujet>` | `hotfix/login-500` | immédiate |

Règles :

- Une branche = une intention. Si la PR mélange deux sujets, elle est à découper.
- Rebase plutôt que merge pour se mettre à jour :
  `git pull --rebase origin main`.
- La branche est supprimée après le merge (squash).

## Commits

Convention **Conventional Commits**, en français, à l'impératif :

```
feat: bracket en double élimination
fix: préflight CORS rejeté sur /api/registrations
chore: passe Keycloak en 26.7.0
docs: runbook de mise en production
test: couvre la propagation du vainqueur
refactor: extrait le calcul des seeds
```

Un commit doit rester atomique et compilable. `style:` est réservé aux
reformatages automatiques (`ktlintFormat`, `cargo fmt`), jamais mélangé à du
code métier.

## Pull requests

1. Ouvrir la PR dès le premier commit (statut brouillon si besoin) : la CI
   tourne et donne un retour immédiat.
2. La PR décrit **quoi** et **pourquoi**, et coche la checklist du gabarit.
3. Conditions de merge (imposées par les règles de protection de `main`) :
   - CI verte (lint + tests, et `terraform plan` pour `infra`) ;
   - au moins une relecture approuvée ;
   - branche à jour avec `main` ;
   - aucune conversation non résolue.
4. Merge en **squash** : un commit par PR sur `main`, historique lisible.

## Ordre entre les repos

Une fonctionnalité qui traverse plusieurs briques se pousse dans cet ordre, pour
que `main` reste cohérent à chaque étape :

```
infra  →  backend  →  worker  →  frontend
(schéma, IAC)  (API)   (jobs)    (écrans)
```

Le frontend ne doit jamais être fusionné avant l'API qu'il consomme : sinon
`main` est déployable en apparence mais l'écran est cassé en production.

## Protection de `main`

Règles actives sur les 4 repos (visibles dans *Settings → Rules*) :

- pas de push direct : tout passe par une pull request ;
- checks CI obligatoires avant merge ;
- une approbation minimum ;
- pas de force-push, pas de suppression de branche ;
- historique linéaire (squash uniquement) ;
- **les administrateurs du repo peuvent contourner** (`bypass_actors`).

Le contournement admin est un choix assumé : à trois sur le projet, avec des
créneaux de travail décalés, exiger une relecture pour un correctif de
production bloquerait la mise en ligne. La règle reste active pour tous — PR
obligatoire et CI verte — et un contournement est tracé dans l'historique des
règles (*Settings → Rules → Insights*). En binôme disponible, la relecture reste
la voie normale.

> Ces règles nécessitent des repos **publics** sur une organisation GitHub
> gratuite. C'est la raison pour laquelle les 4 repos du projet sont publics —
> et pourquoi aucun secret ne doit jamais entrer dans l'historique (voir plus bas).

## Ce qui ne rentre jamais dans git

- fichiers `.env` (seuls les `.env.example` sont versionnés) ;
- clés de comptes de service, tokens, mots de passe — l'authentification des
  pipelines passe par la fédération d'identité, les secrets applicatifs par
  Secret Manager ;
- états Terraform (`*.tfstate`) ;
- dossiers d'IDE (`.idea/`), artefacts de build (`build/`, `target/`, `dist/`,
  `node_modules/`).

En cas de secret poussé par erreur : le révoquer immédiatement chez l'émetteur
(le réécrire dans l'historique ne suffit pas, il est déjà public).

## Hotfix en production

```bash
git switch -c hotfix/login-500 main
# correctif minimal + test de non-régression
gh pr create --fill --label hotfix
# après merge : la CI publie l'image, puis
gh workflow run deploy-prod.yml --repo PA-4AL/<repo> -f image_tag=sha-<sha>
```

Si le correctif prend plus de quelques minutes, **revenir d'abord en arrière**
(`gcloud run services update-traffic … --to-revisions <precedente>=100`) puis
corriger sans pression.
