#!/usr/bin/env bash
# =============================================================================
# Configuration GitHub des 4 repos (idempotent).
#
#   - variables de repo pour les pipelines (projet, région, fédération d'identité)
#   - environnement `production` (support d'une validation manuelle)
#   - règles de protection de `main` : PR obligatoire, CI verte (le job de qualité
#     de ci.yml est un check requis), pas de force-push
#
# Les SECRETS (Docker Hub) ne sont pas gérés ici : ils se posent à la main pour
# ne jamais transiter par un fichier ni par l'historique du shell —
#   gh secret set DOCKERHUB_TOKEN --repo PA-4AL/<repo>
#
# Prérequis : `gh auth status` OK avec les droits admin sur l'organisation, et
# le bootstrap Terraform appliqué (ses sorties alimentent les variables).
#
# Usage :
#   cd infra/terraform/bootstrap && terraform output   # pour vérifier
#   PROJECT_ID=<id> ../../scripts/github-setup.sh
# =============================================================================
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID requis}"
REGION="${REGION:-europe-west1}"
ORG="${ORG:-PA-4AL}"
REPOS=("infra" "backend" "worker" "frontend")
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$(dirname "$0")/../terraform/bootstrap}"

echo "→ lecture des sorties du bootstrap Terraform ($BOOTSTRAP_DIR)"
WIF_PROVIDER=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw workload_identity_provider)
WIF_SA_CI=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw sa_ci_email)
WIF_SA_DEPLOY=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw sa_deploy_email)
WIF_SA_TERRAFORM=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw sa_terraform_email)

for repo in "${REPOS[@]}"; do
  echo
  echo "=== $ORG/$repo ==="

  echo "→ variables"
  gh variable set GCP_PROJECT_ID --repo "$ORG/$repo" --body "$PROJECT_ID"
  gh variable set GCP_REGION     --repo "$ORG/$repo" --body "$REGION"
  gh variable set WIF_PROVIDER   --repo "$ORG/$repo" --body "$WIF_PROVIDER"
  gh variable set WIF_SA_CI      --repo "$ORG/$repo" --body "$WIF_SA_CI"
  gh variable set WIF_SA_DEPLOY  --repo "$ORG/$repo" --body "$WIF_SA_DEPLOY"
  [ "$repo" = "infra" ] && gh variable set WIF_SA_TERRAFORM --repo "$ORG/$repo" --body "$WIF_SA_TERRAFORM"

  echo "→ environnement production"
  gh api -X PUT "repos/$ORG/$repo/environments/production" --silent

  echo "→ règle de protection de main"
  # Nom du job de qualité de ci.yml : c'est le « context » du check requis. Il
  # diffère d'un repo à l'autre, d'où cette table.
  case "$repo" in
    frontend) QUALITY_JOB="Lint, types et tests" ;;
    infra)    QUALITY_JOB="Lint IAC et scripts" ;;
    *)        QUALITY_JOB="Lint et tests" ;;
  esac
  RULES=$(cat <<JSON
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "$QUALITY_JOB" }
        ]
      }
    }
  ]
}
JSON
)
  # Remplace la règle si elle existe déjà (même nom), sinon la crée.
  EXISTING=$(gh api "repos/$ORG/$repo/rulesets" --jq '.[] | select(.name=="main") | .id' 2>/dev/null || true)
  if [ -n "$EXISTING" ]; then
    echo "$RULES" | gh api -X PUT "repos/$ORG/$repo/rulesets/$EXISTING" --input - --silent
    echo "  règle mise à jour (id $EXISTING)"
  else
    echo "$RULES" | gh api -X POST "repos/$ORG/$repo/rulesets" --input - --silent
    echo "  règle créée"
  fi
  echo "  check requis : « $QUALITY_JOB »"
done

echo
echo "✓ Terminé. Restent à poser à la main, une fois par repo :"
echo "    gh secret set DOCKERHUB_USERNAME --repo $ORG/<repo>"
echo "    gh secret set DOCKERHUB_TOKEN    --repo $ORG/<repo>"
