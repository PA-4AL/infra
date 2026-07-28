# =============================================================================
# Keycloak — image « optimisée » pour Cloud Run.
# Contexte de build attendu : le repo infra/ (docker build -f docker/keycloak.Dockerfile .)
#
# Pourquoi une image custom plutôt que quay.io/keycloak/keycloak directement :
#   1. `kc.sh build` est exécuté au BUILD (augmentation Quarkus) : au démarrage,
#      `start --optimized` ne refait plus cette étape → cold start divisé par
#      ~3, ce qui compte sur Cloud Run avec scale-to-zero ;
#   2. le realm (clients, rôles, SSO Google/Discord) et le thème `pa` sont
#      embarqués : l'authentification est reproductible, versionnée dans git,
#      et non configurée à la main dans une console d'admin.
#
# Tag : 26.7.0 épinglé au patch. Image officielle du projet Keycloak (CNCF,
# publiée par Red Hat sur quay.io) — pas un rebuild tiers.
# =============================================================================

FROM quay.io/keycloak/keycloak:26.7.0 AS build

# Augmentation pour PostgreSQL uniquement (les autres pilotes sont retirés).
RUN /opt/keycloak/bin/kc.sh build --db=postgres


FROM quay.io/keycloak/keycloak:26.7.0 AS runtime

COPY --from=build /opt/keycloak/ /opt/keycloak/

# Realm importé au premier démarrage (stratégie par défaut : on n'écrase pas un
# realm déjà présent, donc les comptes créés en prod survivent aux redéploiements).
COPY keycloak/realm-pa-tournament.json /opt/keycloak/data/import/realm-pa-tournament.json
COPY keycloak/themes/pa /opt/keycloak/themes/pa

# Cloud Run : un seul port exposé, TLS terminé en amont par le frontal Google.
ENV KC_HTTP_ENABLED=true \
    KC_HTTP_PORT=8080 \
    KC_PROXY_HEADERS=xforwarded \
    KC_DB=postgres

EXPOSE 8080

# L'image de base tourne déjà en utilisateur non-root (UID 1000).
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start", "--optimized", "--import-realm"]
