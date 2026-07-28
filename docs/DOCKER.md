# Images Docker — choix et optimisations

Les quatre livrables du projet sont des images de conteneur. Ce document
justifie, pour chacune, l'image de base, le tag, l'ordre des couches et le mode
d'exécution.

| Service | Dockerfile | Image de base d'exécution | Taille |
|---|---|---|---|
| frontend | `frontend/Dockerfile` | `nginxinc/nginx-unprivileged:1.31.2-alpine` | **54,2 Mo** |
| backend | `backend/Dockerfile` | `eclipse-temurin:21.0.10_7-jre-alpine` | **254 Mo** |
| worker | `worker/Dockerfile` | `gcr.io/distroless/cc-debian12:nonroot` | **33,4 Mo** |
| keycloak | `infra/docker/keycloak.Dockerfile` | `quay.io/keycloak/keycloak:26.7.0` | 669 Mo |

Tailles mesurées localement (`docker images`), architecture `linux/amd64`.

## Fiabilité et provenance des images de base

| Image | Éditeur | Maintenance |
|---|---|---|
| `node:22.21.1-alpine` | Docker Official Image (Node.js) | reconstruite à chaque patch de Node ; 22 est une version LTS |
| `nginxinc/nginx-unprivileged` | **NGINX Inc.** (éditeur du serveur) | dépôt officiel du projet, variante sans root |
| `eclipse-temurin` | Eclipse Adoptium (Eclipse Foundation) | distribution OpenJDK de référence, mises à jour trimestrielles de sécurité |
| `gcr.io/distroless/cc-debian12` | **Google** | reconstruite automatiquement à chaque correctif Debian |
| `rust:1.97.1-slim-bookworm` | Docker Official Image (Rust) | suit les publications stables |
| `quay.io/keycloak/keycloak` | **Red Hat / projet Keycloak (CNCF)** | image amont officielle, pas un rebuild tiers |

Aucune image de base issue d'un compte personnel ou non maintenu.

## Choix des tags

Règle du projet : **un tag épinglé au patch, jamais `latest`**.

- `latest` rend un build non reproductible : deux `docker build` à un mois
  d'écart peuvent produire deux images différentes à partir du même code.
- Un tag flottant de branche (`21-jre-alpine`, `1.31-alpine`) est plus stable
  mais bouge quand même — un correctif de base peut casser un build en CI sans
  aucun changement de code.

Un cas concret rencontré dans ce projet : l'ancien `worker.Dockerfile` était
figé sur `rust:1.85`. Ce tag **ne compile plus le worker** aujourd'hui (vérifié
en reconstruisant l'ancienne image) — les dépendances ont avancé :

```
error: rustc 1.85.1 is not supported by the following packages:
  home@0.5.12 requires rustc 1.88
  icu_collections@2.2.0 requires rustc 1.86
```

D'où la double règle : **épingler au patch** (`1.97.1`) *et* **remonter
volontairement** cette version dans un commit dédié (`chore: passe Rust en
1.97.1`), en gardant la CI comme filet.

Exception assumée : les étages de **build** utilisent parfois un tag mineur
(`eclipse-temurin:21-jdk`) car l'image est jetée à la fin ; ce qui compte pour la
reproductibilité du binaire produit, c'est la version du wrapper Gradle (9.3),
elle-même versionnée dans le repo.

## Optimisation de la taille

### Multi-stage systématique

Les quatre images ont un étage de build et un étage d'exécution. Les outils de
compilation ne partent jamais en production :

| Étage de build | Taille de la base | Présent en production ? |
|---|---|---|
| `node:22.21.1-alpine` (npm, Vite, TypeScript) | 136 Mo | non |
| `eclipse-temurin:21-jdk` (JDK complet, Gradle) | ~460 Mo | non |
| `rust:1.97.1-slim-bookworm` (cargo, rustc) | ~800 Mo | non |

### Avant / après (images réellement construites et mesurées)

| Image finale | Avant | Après | Écart |
|---|---|---|---|
| backend | **364 Mo** | **254 Mo** | **−110 Mo (−30 %)** |
| worker | *ne compile plus* (voir ci-dessus) | **33,4 Mo** | base d'exécution 74,8 Mo → 33,4 Mo |
| frontend | 48,6 Mo | 54,2 Mo | **+5,6 Mo — assumé**, voir ci-dessous |

Le frontend **grossit** : c'est le prix de deux décisions volontaires — passer de
`nginx:1.27-alpine` à `nginx-unprivileged:1.31.2-alpine` (nginx plus récent, et
surtout aucun processus root dans le conteneur). Sur une image servie depuis un
registre régional et mise en cache par Cloud Run, 5 Mo ne coûtent rien ; un
serveur web tournant en root, si.

Autres changements sur les étages de build :

| Élément | Avant | Après | Effet |
|---|---|---|---|
| Base de build du backend | `gradle:8-jdk21` — 803 Mo | `eclipse-temurin:21-jdk` + wrapper du repo | Gradle 9.3, la même version qu'en local et en CI (l'ancienne image était en Gradle 8, incohérente avec le projet) |
| Contexte de build | tout le repo (`build/`, `.gradle/`, `node_modules/`, `.git/`) | `.dockerignore` dans les 3 repos | ~6,3 Mo → ~0,7 Mo côté backend |
| Couche modifiée à chaque commit (backend) | le jar complet (~60 Mo) | couche `application` | **970 ko** |

L'ancien `backend.Dockerfile` était par ailleurs **incohérent** : il utilisait
`gradle:8-jdk21` alors que le projet exige Gradle 9.3 (`gradle-wrapper.properties`).
Le nouveau Dockerfile appelle `./gradlew`, donc la même version qu'en local et en CI.

### Cas particulier du backend : jar en couches

Au lieu de copier un jar « gras » de ~60 Mo en une seule couche, le jar est
décomposé par Spring Boot :

```dockerfile
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted
...
COPY --from=build /app/extracted/dependencies/ ./          # stable
COPY --from=build /app/extracted/spring-boot-loader/ ./     # stable
COPY --from=build /app/extracted/snapshot-dependencies/ ./  # semi-stable
COPY --from=build /app/extracted/application/ ./            # change à chaque commit
```

Résultat mesuré : la couche applicative pèse **970 ko**. Un déploiement ne
transfère donc que ~1 Mo au lieu de 60 Mo, ce qui accélère aussi le démarrage
d'une révision Cloud Run (moins de données à extraire).

## Optimisation du cache Docker

Principe appliqué partout : **ce qui change rarement est copié en premier**.

```dockerfile
# frontend
COPY package.json package-lock.json ./
RUN npm ci            # ← rejoué seulement si le lockfile change
COPY . .
RUN npm run build

# backend
COPY gradlew ./ ; COPY gradle ./gradle
RUN ./gradlew --version                     # télécharge la distribution Gradle
COPY settings.gradle build.gradle ./
RUN ./gradlew dependencies …                # ← rejoué seulement si le build change
COPY src ./src
RUN ./gradlew bootJar -x test

# worker
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && cargo build --release --locked
COPY src ./src                              # ← seul le crate du worker est recompilé
```

Sans ce découpage, un changement d'une ligne de code réinstallerait toutes les
dépendances npm / Gradle / Cargo. Les pipelines complètent avec
`cache-from/to: type=gha`, qui rend ces couches persistantes d'un run à l'autre.

## Build de production, jamais de serveur de développement

- frontend : `npm run build` (`tsc -b && vite build`), servi ensuite par nginx.
  Aucun `npm run dev`, aucune dépendance de développement dans l'image finale.
- backend : `bootJar` en mode release ; `spring-boot-devtools` est déclaré
  `developmentOnly` et n'est donc pas embarqué.
- worker : `cargo build --release --locked` puis `strip` du binaire.
- keycloak : `kc.sh build` puis `start --optimized` — surtout pas `start-dev`
  (base H2 embarquée, désactivation de vérifications, thèmes non mis en cache).

## Exécution non privilégiée

| Image | Utilisateur |
|---|---|
| frontend | UID 101 (image `nginx-unprivileged`) |
| backend | utilisateur `spring` créé dans le Dockerfile |
| worker | UID 65532 (`distroless:nonroot`), et **aucun shell dans l'image** |
| keycloak | UID 1000 (image amont) |

Ports : tous les services écoutent sur **8080**, ce qu'attend Cloud Run.

## Reproductibilité et vérification

```bash
# frontend
docker build -t pa-frontend:test frontend
docker run --rm -p 8080:8080 -e API_URL=https://api.exemple.fr pa-frontend:test
curl localhost:8080/health      # → ok
curl localhost:8080/config.js    # → window.__APP_CONFIG__ avec les bonnes URLs

# worker (l'erreur de configuration prouve que le binaire tourne bien sur distroless)
docker build -t pa-worker:test worker
docker run --rm pa-worker:test   # → Config error: GCP_PROJECT_ID not set

# backend, avec une base jetable
docker build -t pa-backend:test backend
docker network create pa-test
docker run -d --rm --name db --network pa-test -e POSTGRES_USER=pa -e POSTGRES_PASSWORD=pa -e POSTGRES_DB=pa postgres:16
docker run --rm --network pa-test -p 8080:8080 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/pa \
  -e SPRING_DATASOURCE_USERNAME=pa -e SPRING_DATASOURCE_PASSWORD=pa pa-backend:test
curl localhost:8080/actuator/health   # → {"status":"UP"}
```

## Pistes non retenues aujourd'hui

- **Worker en musl/rustls + `distroless/static`** : gagnerait encore ~25 Mo et
  supprimerait la dépendance à OpenSSL, mais impose de basculer la pile TLS de
  `native-tls` vers `rustls` dans les dépendances Pub/Sub.
- **`jlink` pour le backend** : un runtime Java réduit aux modules utilisés
  ferait descendre l'image sous 150 Mo, au prix d'une configuration à maintenir.
- **Analyse de vulnérabilités (Trivy) en CI** : quelques lignes à ajouter au job
  `image`, non fait par manque de temps.
- **Images multi-architectures** : inutile ici, Cloud Run est en `amd64`.
