#!/usr/bin/env bash
# =============================================================================
# Configuration post-déploiement du realm Keycloak (idempotent).
#
# Le realm de base (clients, rôles, thème) est importé depuis
# keycloak/realm-pa-tournament.json au premier démarrage du conteneur. Ce
# fichier ne contient QUE des valeurs de développement : ni URL de production,
# ni secret. Ce script applique la couche « environnement » via l'API d'admin :
#
#   - URIs de redirection et origines CORS du client public pa-frontend
#   - identifiants des fournisseurs SSO Google et Discord
#
# Pourquoi un script et pas des placeholders dans le JSON : la substitution
# ${env.X} à l'import n'est pas fiable côté Keycloak 26 (testée, non appliquée),
# et l'import est ignoré si le realm existe déjà — donc inutilisable pour faire
# évoluer la conf. Ici on est idempotent et rejouable à volonté.
#
# Usage :
#   KEYCLOAK_URL=https://auth.exemple.fr \
#   KC_ADMIN=admin KC_ADMIN_PASSWORD=... \
#   APP_ORIGIN=https://app.exemple.fr \
#   [GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=...] \
#   [DISCORD_CLIENT_ID=... DISCORD_CLIENT_SECRET=...] \
#   ./scripts/keycloak-configure.sh
# =============================================================================
set -euo pipefail

: "${KEYCLOAK_URL:?URL publique de Keycloak requise (ex: https://auth.exemple.fr)}"
: "${KC_ADMIN:?compte admin requis}"
: "${KC_ADMIN_PASSWORD:?mot de passe admin requis}"
: "${APP_ORIGIN:?origine du frontend requise (ex: https://app.exemple.fr)}"
REALM="${REALM:-pa-tournament}"
FRONTEND_CLIENT="${FRONTEND_CLIENT:-pa-frontend}"

api() { # api <method> <path> [data]
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS --fail-with-body -X "$method" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$data" "$KEYCLOAK_URL/admin/realms$path"
  else
    curl -sS --fail-with-body -X "$method" \
      -H "Authorization: Bearer $TOKEN" "$KEYCLOAK_URL/admin/realms$path"
  fi
}

echo "→ authentification sur $KEYCLOAK_URL"
TOKEN=$(curl -sS --fail-with-body \
  -d "client_id=admin-cli" -d "username=$KC_ADMIN" \
  --data-urlencode "password=$KC_ADMIN_PASSWORD" -d "grant_type=password" \
  "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" | jq -r .access_token)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "échec de l'authentification admin sur $KEYCLOAK_URL" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 0) Durée des sessions
#
# Les défauts de Keycloak déconnectent au bout de 30 minutes d'inactivité, pour
# 10 heures au maximum. Exigence du projet : rester connecté au moins 12 heures
# sans avoir à se réauthentifier, y compris après une longue inactivité — d'où
# une inactivité tolérée de 12 h et une session plafonnée à 24 h.
#
# La durée du jeton d'accès reste courte (5 min) : le frontend le renouvelle en
# silence avant chaque appel (`updateToken(30)`), et un jeton volé expire vite.
# C'est la session, pas le jeton, qui porte les 12 heures.
#
# « Se souvenir de moi » est activé : les utilisateurs qui le cochent tiennent
# 24 h d'inactivité et 48 h en tout.
#
# Ces valeurs figurent aussi dans keycloak/realm-pa-tournament.json, mais
# l'import est ignoré quand le realm existe déjà : sans ce bloc, la production
# resterait sur les défauts.
# ---------------------------------------------------------------------------
echo "→ realm $REALM : durée des sessions"
REALM_CONF=$(api GET "/$REALM")
api PUT "/$REALM" "$(echo "$REALM_CONF" | jq -c '
    .rememberMe                      = true
  | .ssoSessionIdleTimeout           = 43200
  | .ssoSessionMaxLifespan           = 86400
  | .ssoSessionIdleTimeoutRememberMe = 86400
  | .ssoSessionMaxLifespanRememberMe = 172800
  | .accessTokenLifespan             = 300')" >/dev/null
echo "  inactivité tolérée 12 h · session 24 h max · jeton d'accès 5 min"

# ---------------------------------------------------------------------------
# 1) Client public : URIs de redirection + origines CORS
# ---------------------------------------------------------------------------
echo "→ client $FRONTEND_CLIENT : ajout de $APP_ORIGIN"
CLIENT=$(api GET "/$REALM/clients?clientId=$FRONTEND_CLIENT" | jq '.[0]')
CLIENT_UUID=$(echo "$CLIENT" | jq -r .id)
[ "$CLIENT_UUID" != "null" ] || { echo "client $FRONTEND_CLIENT introuvable" >&2; exit 1; }

PAYLOAD=$(echo "$CLIENT" | jq \
  --arg redirect "$APP_ORIGIN/*" --arg origin "$APP_ORIGIN" '
  .redirectUris = ((.redirectUris // []) + [$redirect] | unique)
  | .webOrigins  = ((.webOrigins  // []) + [$origin]   | unique)')
api PUT "/$REALM/clients/$CLIENT_UUID" "$PAYLOAD" >/dev/null
echo "  redirectUris : $(echo "$PAYLOAD" | jq -c .redirectUris)"

# ---------------------------------------------------------------------------
# 2) Fournisseurs SSO (spec §4.5) — seulement si les secrets sont fournis
# ---------------------------------------------------------------------------
configure_idp() { # configure_idp <alias> <client_id> <client_secret>
  local alias="$1" id="$2" secret="$3"
  if [ -z "$id" ] || [ -z "$secret" ]; then
    echo "→ SSO $alias : ignoré (identifiants non fournis)"
    return
  fi
  echo "→ SSO $alias : mise à jour des identifiants"
  local idp
  idp=$(api GET "/$REALM/identity-provider/instances/$alias")
  local payload
  payload=$(echo "$idp" | jq --arg id "$id" --arg secret "$secret" \
    '.enabled = true | .config.clientId = $id | .config.clientSecret = $secret')
  api PUT "/$REALM/identity-provider/instances/$alias" "$payload" >/dev/null
}

configure_idp google "${GOOGLE_CLIENT_ID:-}" "${GOOGLE_CLIENT_SECRET:-}"
configure_idp discord "${DISCORD_CLIENT_ID:-}" "${DISCORD_CLIENT_SECRET:-}"

# ---------------------------------------------------------------------------
# 3) Durcissement : le realm versionné contient des valeurs de développement
#    connues de tous (le repo est public). Elles ne doivent pas survivre en prod.
# ---------------------------------------------------------------------------

# 3a) Comptes de démonstration (demo / joueur, mots de passe dans le JSON du realm)
if [ "${DISABLE_DEMO_USERS:-true}" = "true" ]; then
  for username in demo joueur; do
    user_id=$(api GET "/$REALM/users?username=$username&exact=true" | jq -r '.[0].id // empty')
    if [ -n "$user_id" ]; then
      enabled=$(api GET "/$REALM/users/$user_id" | jq -r .enabled)
      if [ "$enabled" = "true" ]; then
        echo "→ compte de démonstration « $username » : désactivé"
        api PUT "/$REALM/users/$user_id" '{"enabled":false}' >/dev/null
      else
        echo "→ compte de démonstration « $username » : déjà désactivé"
      fi
    fi
  done
else
  echo "→ comptes de démonstration conservés (DISABLE_DEMO_USERS=false)"
fi

# 3b) Secret du client confidentiel pa-backend, livré à « change-me-in-prod »
BACKEND_CLIENT_UUID=$(api GET "/$REALM/clients?clientId=pa-backend" | jq -r '.[0].id // empty')
if [ -n "$BACKEND_CLIENT_UUID" ]; then
  current=$(api GET "/$REALM/clients/$BACKEND_CLIENT_UUID/client-secret" | jq -r '.value // empty')
  if [ "$current" = "change-me-in-prod" ]; then
    echo "→ client pa-backend : régénération du secret par défaut"
    api POST "/$REALM/clients/$BACKEND_CLIENT_UUID/client-secret" '{}' >/dev/null
    echo "  nouveau secret lisible via : GET /admin/realms/$REALM/clients/$BACKEND_CLIENT_UUID/client-secret"
  else
    echo "→ client pa-backend : secret déjà personnalisé"
  fi
fi

echo
echo "✓ realm $REALM configuré."
echo "  Pensez à déclarer ces URIs de callback côté fournisseurs :"
echo "    Google  : $KEYCLOAK_URL/realms/$REALM/broker/google/endpoint"
echo "    Discord : $KEYCLOAK_URL/realms/$REALM/broker/discord/endpoint"
