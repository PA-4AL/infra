# ============================================================
# PA Tournament — Orchestration locale
# Prérequis : backend/, worker/, frontend/, infra/ côte à côte.
#
#   make dev    → tout lancer en local (Ctrl+C arrête tout)
#   make full   → tout lancer en conteneurs Docker
# ============================================================

.DEFAULT_GOAL := help
ROOT    := $(abspath ..)
COMPOSE := docker compose

# Identifiants de la base (alignés sur docker-compose.yml / .env)
DB_URL  := jdbc:postgresql://localhost:5432/pa
DB_USER := pa
DB_PASS := pa

.PHONY: help dev infra backend worker frontend full stop clean logs ps

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

# ---------- Dev local (processus natifs + db/keycloak en Docker) ----------

dev: infra ## Lance TOUT en local : db + keycloak (Docker), backend, worker, frontend (Ctrl+C arrête tout)
	$(MAKE) -j3 -k backend worker frontend

infra: ## PostgreSQL + Keycloak seulement (Docker)
	$(COMPOSE) up -d db keycloak

backend: ## Backend Kotlin/Spring (gradle bootRun, branché sur la db de l'infra)
	cd $(ROOT)/backend && \
	JAVA_TOOL_OPTIONS="-Djava.net.preferIPv6Addresses=true" \
	SPRING_DATASOURCE_URL=$(DB_URL) \
	SPRING_DATASOURCE_USERNAME=$(DB_USER) \
	SPRING_DATASOURCE_PASSWORD=$(DB_PASS) \
	sh ./gradlew bootRun --no-daemon

worker: ## Worker Rust (cargo run — nécessite un .env avec les accès GCP Pub/Sub)
	@cd $(ROOT)/worker && \
	([ -f .env ] || (cp .env.example .env && echo ">> worker/.env créé depuis .env.example — renseigne GCP_PROJECT_ID & co")) && \
	cargo run || echo ">> worker arrêté (config GCP manquante ?) — les autres services continuent"

frontend: ## Frontend React (vite dev server → http://localhost:5173)
	@cd $(ROOT)/frontend && \
	([ -d node_modules ] || npm install) && \
	([ -f .env ] || cp .env.example .env) && \
	npm run dev

# ---------- Stack 100% Docker ----------

full: ## Tout en conteneurs (frontend → :3000, backend → :8080, keycloak → :8081)
	$(COMPOSE) --profile full up -d --build

# ---------- Cycle de vie ----------

stop: ## Arrête les conteneurs (db, keycloak, et la stack full le cas échéant)
	$(COMPOSE) --profile full down

clean: stop ## Arrête tout et SUPPRIME le volume de la base
	$(COMPOSE) --profile full down -v

logs: ## Suit les logs des conteneurs
	$(COMPOSE) --profile full logs -f

ps: ## État des conteneurs
	$(COMPOSE) --profile full ps
