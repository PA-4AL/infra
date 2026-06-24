# Plan de commits global — PA4

4 repos coordonnés. Ordre : **infra → backend → worker → frontend**.
Chaque phase s'appuie sur la précédente : le schéma DB de l'infra est la source
de vérité pour le backend (Liquibase + jOOQ) et le worker (table `jobs`).

---

## Pourquoi cet ordre

```
infra       →  DB schema + Docker + Keycloak  (la fondation)
backend     →  Migrations + jOOQ + API        (dépend du schéma)
worker      →  Rust + Pub/Sub + import Excel  (dépend de la table jobs)
frontend    →  React + pages                  (dépend des endpoints API)
```

---

## REPO : infra

```bash
cd /home/alex/Documents/GIT/PA4/infra
```

### I-01 — Variables d'environnement et Makefile

```bash
git add .env.example Makefile
git commit -m "chore: variables d'environnement et Makefile"
```

### I-02 — Schéma PostgreSQL (source de vérité spec §6)

```bash
git add db/schema.sql
git commit -m "feat: schéma PostgreSQL — enums, tables, index"
```

### I-03 — Images Docker backend et worker

```bash
git add docker/backend.Dockerfile docker/worker.Dockerfile
git commit -m "chore: Dockerfiles backend (JRE 21) et worker (Rust musl)"
```

### I-04 — Docker Compose stack complète

```bash
git add docker-compose.yml
git commit -m "feat: docker-compose — db, keycloak, backend, worker, frontend"
```

### I-05 — Realm Keycloak (clients, SSO Google/Discord)

```bash
git add keycloak/realm-pa-tournament.json
git commit -m "feat: realm Keycloak pa-tournament avec SSO Google et Discord"
```

### I-06 — Documentation déploiement Cloud Run

```bash
git add docs/
git commit -m "docs: guide déploiement Cloud Run et specs"
```

### I-07 — README

```bash
git add README.md
git commit -m "docs: README infra"
```

---

## REPO : backend

```bash
cd /home/alex/Documents/GIT/PA4/backend
```

> Le backend a des commits existants avec d'anciens noms de fichiers
> (Matchdb, Playerdb, Usersdb…). Le premier commit ci-dessous nettoie ça.

### B-01 — Mise à jour Gradle + config JVM 21

```bash
git add build.gradle gradlew gradle/wrapper/gradle-wrapper.properties
git commit -m "chore: Gradle 9.3, Spring Boot 4, JVM target 21"
```

### B-02 — Suppression anciens modèles + application.yml

```bash
git rm src/main/kotlin/org/example/backend/database/tables/Matchdb.kt
git rm src/main/kotlin/org/example/backend/database/tables/Playerdb.kt
git rm src/main/kotlin/org/example/backend/database/tables/Tournamentdb.kt
git rm src/main/kotlin/org/example/backend/database/tables/Usersdb.kt
git rm src/main/kotlin/org/example/backend/database/tables/records/MatchdbRecord.kt
git rm src/main/kotlin/org/example/backend/database/tables/records/PlayerdbRecord.kt
git rm src/main/kotlin/org/example/backend/database/tables/records/TournamentdbRecord.kt
git rm src/main/kotlin/org/example/backend/database/tables/records/UsersdbRecord.kt
git rm src/main/kotlin/org/example/backend/model/Match.kt
git rm src/main/kotlin/org/example/backend/model/Player.kt
git rm src/main/kotlin/org/example/backend/model/Tournament.kt
git add src/main/resources/application.yml
git commit -m "refactor: suppression anciens modèles, mise à jour application.yml"
```

### B-03 — Migrations Liquibase

```bash
git add src/main/resources/db/
git commit -m "feat: migrations Liquibase — schéma initial, seed démo, avatar"
```

### B-04 — jOOQ : enums générés

```bash
git add src/main/kotlin/org/example/backend/database/enums/
git commit -m "feat: jOOQ — enums PostgreSQL générés (13 types)"
```

### B-05 — jOOQ : tables et records générés

```bash
git add src/main/kotlin/org/example/backend/database/tables/
git add src/main/kotlin/org/example/backend/database/indexes/
git add src/main/kotlin/org/example/backend/database/Public.kt
git add src/main/kotlin/org/example/backend/database/DefaultCatalog.kt
git add src/main/kotlin/org/example/backend/database/keys/Keys.kt
git commit -m "feat: jOOQ — tables et records générés depuis le schéma spec §6"
```

### B-06 — Sécurité OAuth2 / Keycloak

```bash
git add src/main/kotlin/org/example/backend/config/
git commit -m "feat: sécurité OAuth2 resource server Keycloak"
```

### B-07 — DTOs

```bash
git add src/main/kotlin/org/example/backend/model/
git commit -m "feat: DTOs — Tournament, Bracket, Registration, Profile, Team, Dashboard"
```

### B-08 — Repositories jOOQ

```bash
git add src/main/kotlin/org/example/backend/repository/TournamentRepository.kt
git add src/main/kotlin/org/example/backend/repository/BracketRepository.kt
git add src/main/kotlin/org/example/backend/repository/RegistrationRepository.kt
git add src/main/kotlin/org/example/backend/repository/ProfileRepository.kt
git add src/main/kotlin/org/example/backend/repository/TeamRepository.kt
git commit -m "feat: repositories jOOQ — tournaments, bracket, registrations, profile, teams"
```

### B-09 — Services métier

```bash
git add src/main/kotlin/org/example/backend/service/TournamentService.kt
git add src/main/kotlin/org/example/backend/service/BracketService.kt
git add src/main/kotlin/org/example/backend/service/RegistrationService.kt
git add src/main/kotlin/org/example/backend/service/ProfileService.kt
git add src/main/kotlin/org/example/backend/service/TeamService.kt
git add src/main/kotlin/org/example/backend/service/DashboardService.kt
git commit -m "feat: services — logique métier tournois, bracket, inscriptions, profil, équipes"
```

### B-10 — Controllers REST

```bash
git add src/main/kotlin/org/example/backend/controller/TournamentController.kt
git add src/main/kotlin/org/example/backend/controller/BracketController.kt
git add src/main/kotlin/org/example/backend/controller/RegistrationController.kt
git add src/main/kotlin/org/example/backend/controller/ProfileController.kt
git add src/main/kotlin/org/example/backend/controller/TeamController.kt
git add src/main/kotlin/org/example/backend/controller/DashboardController.kt
git commit -m "feat: controllers REST — tous les endpoints spec §5"
```

### B-11 — Point d'entrée et tests

```bash
git add src/main/kotlin/org/example/backend/BackendApplication.kt
git add src/test/
git commit -m "feat: application Spring Boot et tests de démarrage"
```

### B-12 — Documentation

```bash
git add docs/
git commit -m "docs: LIQUIBASE.md et specs"
```

### B-13 — README

```bash
git add README.md
git commit -m "docs: README backend"
```

---

## REPO : worker

```bash
cd /home/alex/Documents/GIT/PA4/worker
```

### W-01 — Config projet Rust

```bash
git add Cargo.toml Cargo.lock .env.example
git commit -m "chore: init projet Rust — dépendances Tokio, Pub/Sub, Calamine"
```

### W-02 — Config et erreurs

```bash
git add src/config.rs src/errors.rs
git commit -m "feat: config depuis env et types d'erreurs"
```

### W-03 — Modèles de messages

```bash
git add src/models.rs
git commit -m "feat: modèles Pub/Sub — IncomingMessage, TaskResponse"
```

### W-04 — File de messages Pub/Sub (consumer + producer)

```bash
git add src/queue/
git commit -m "feat: queue Pub/Sub — consumer pull et producer publish"
```

### W-05 — Retry

```bash
git add src/retry/
git commit -m "feat: logique de retry avec backoff exponentiel"
```

### W-06 — Parsers Excel (esport + football)

```bash
git add src/parser/
git commit -m "feat: parsers Excel — esport et football via Calamine"
```

### W-07 — Tasks et dispatcher

```bash
git add src/tasks/
git commit -m "feat: tasks — dispatcher, import Excel vers DB"
```

### W-08 — Point d'entrée et graceful shutdown

```bash
git add src/main.rs
git commit -m "feat: main — boucle Tokio, SIGINT/SIGTERM, shutdown propre"
```

### W-09 — Documentation technique

```bash
git add DOC.md DOC_TECHNIQUE.md PROJET.md REVIEW.md docs/
git commit -m "docs: documentation technique et specs worker"
```

---

## REPO : frontend (suite — commits 09 à 22)

```bash
cd /home/alex/Documents/GIT/PA4/frontend
```

> Les commits 01 à 08 sont déjà faits.

### F-09 — Design system CSS

```bash
git add src/styles/pa.css src/styles/pages.css
git commit -m "feat: design system CSS — tokens, layout, composants"
```

### F-10 — Composants UI

```bash
git add src/components/ui.tsx
git commit -m "feat: composants UI — Avatar, StatusBadge, FmtBadge"
```

### F-11 — Shell (layout principal)

```bash
git add src/components/Shell.tsx
git commit -m "feat: Shell — layout principal, sidebar, topnav"
```

### F-12 — Page connexion

```bash
git add src/pages/LoginPage.tsx
git commit -m "feat: page connexion avec SSO Google et Discord"
```

### F-13 — Tableau de bord

```bash
git add src/pages/DashboardPage.tsx
git commit -m "feat: tableau de bord — KPIs, liste tournois, fil activité"
```

### F-14 — Création de tournoi

```bash
git add src/pages/CreateTournamentPage.tsx
git commit -m "feat: création de tournoi — formulaire multi-jeu"
```

### F-15 — Détail tournoi

```bash
git add src/pages/TournamentDetailPage.tsx
git commit -m "feat: détail tournoi — phases, matchs en cours, admin panel"
```

### F-16 — Bracket interactif

```bash
git add src/pages/BracketPage.tsx
git commit -m "feat: bracket interactif — pan, zoom, saisie de score"
```

### F-17 — Gestion participants

```bash
git add src/pages/ParticipantsPage.tsx
git commit -m "feat: gestion participants — inscription, seeds, validation"
```

### F-18 — Validations

```bash
git add src/pages/ValidationsPage.tsx
git commit -m "feat: validations — file d'attente d'inscriptions"
```

### F-19 — Profil utilisateur

```bash
git add src/pages/ProfilePage.tsx
git commit -m "feat: profil — avatar, pseudo, comptes in-game, historique"
```

### F-20 — Équipes

```bash
git add src/pages/TeamsPage.tsx
git commit -m "feat: équipes — roster, capitaine, gestion membres"
```

### F-21 — Routeur principal

```bash
git add src/App.tsx src/main.tsx src/vite-env.d.ts
git commit -m "feat: routeur principal et point d'entrée React"
```

### F-22 — Documentation

```bash
git add docs/ mockups/ README.md
git commit -m "docs: specs fonctionnelles et maquettes de référence"
```

---

## Push final (les 4 repos)

```bash
git -C /home/alex/Documents/GIT/PA4/infra    push origin main
git -C /home/alex/Documents/GIT/PA4/backend  push origin main
git -C /home/alex/Documents/GIT/PA4/worker   push origin main
git -C /home/alex/Documents/GIT/PA4/frontend push origin main
```

---

## Récap par repo

| Repo | Commits | Stack |
|---|---|---|
| infra | 7 | Docker · PostgreSQL · Keycloak |
| backend | 13 | Kotlin · Spring Boot 4 · jOOQ · Liquibase |
| worker | 9 | Rust · Tokio · Google Pub/Sub · Calamine |
| frontend | 14 | React 19 · TypeScript · Vite 6 |
| **Total** | **43** | |
