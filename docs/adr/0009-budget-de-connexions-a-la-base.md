# ADR-0009 — Borner les pools de connexions, et vérifier le budget au `plan`

- **Date** : 2026-07-29
- **Statut** : accepté
- **Portée** : infra

## Contexte

Une panne de production a révélé une hypothèse jamais posée. Le backend ne
démarrait plus, Liquibase échouant sur `FATAL: remaining connection slots are
reserved for roles with privileges of the "pg_use_reserved_connections" role`.
Les instances déjà chaudes continuaient de servir les lectures, si bien que le
site paraissait fonctionner alors que toute écriture échouait sans message.

L'arithmétique n'avait jamais pu tenir. Un `db-f1-micro` plafonne à environ 25
connexions, et aucun pool n'était borné :

| Service | Instances max | Pool par instance | Total possible |
|---|---|---|---|
| backend | 4 | 10 *(défaut HikariCP)* | 40 |
| keycloak | 2 | 100 *(défaut Keycloak 26)* | 200 |

Cela tenait par chance tant qu'une seule instance tournait. Le pire cas n'est
d'ailleurs pas le trafic de pointe mais **le déploiement** : Cloud Run fait
tourner l'ancienne et la nouvelle révision en parallèle le temps de basculer le
trafic, ce qui double la demande au moment précis où l'on croit ne rien risquer.

## Décision

Trois mesures, toutes dans l'IaC pour qu'elles survivent au prochain `apply`.

**Borner les pools plutôt que gonfler la base.** 3 connexions par instance de
backend, 5 par instance de Keycloak. Les requêtes sont courtes ; un pool large
n'apporte rien et confisque une ressource partagée. `minimum-idle` à 1 et une
durée de vie plafonnée rendent les connexions inutilisées au lieu de les
immobiliser.

**Rendre `max_connections` explicite** (60) au lieu de subir le défaut implicite
du gabarit. La valeur reste modeste à dessein : chaque connexion PostgreSQL coûte
de la mémoire, et l'instance n'en a que 0,6 Go — le plafond n'est pas la solution,
seulement un filet.

**Faire échouer le `plan` si le budget est intenable.** Une précondition
`terraform_data` calcule le pire cas — pools × instances × deux révisions +
accès d'exploitation + réserve superuser — et le compare au plafond. En
production : 55 pour 60.

Options écartées : augmenter le gabarit Cloud SQL (coût, et le vrai défaut reste
non corrigé) ; un pooler type PgBouncer (une brique de plus à exploiter pour un
projet de cette taille) ; ne rien changer et surveiller (la panne était muette
côté utilisateur, une alerte serait arrivée après lui).

## Conséquences

- la panne ne peut plus se reproduire en silence : augmenter `max_instances`
  sans revoir les pools fait échouer Terraform, avec le calcul affiché ;
- le budget cesse d'être une évidence tacite dans la tête de celui qui a monté
  l'infra — il est écrit, chiffré et vérifié à chaque `plan` ;
- appliquer `max_connections` **redémarre l'instance Cloud SQL** : ce n'est pas
  une modification à faire à chaud sans prévenir ;
- les pools étroits interdisent d'encaisser une charge élevée sans repasser par
  cette décision. C'est voulu : sur ce gabarit, la limite serait de toute façon
  atteinte ailleurs.
