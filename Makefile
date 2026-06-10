COMPOSE ?= docker compose
COMPOSE_FILES ?= -f docker-compose.yml

# Detect available compose files and build dynamic targets
AVAILABLE_COMPOSES := $(wildcard compose/*.yml)

.PHONY: help init build-base config up shell down ps logs \
        db cache mq storage registry observability ci gateway docs \
        go-env rust-env php-env full-env dev check lock

# Service names that can be passed positionally to the preset targets
# (e.g., `make rust-env mysql redis`). Listing them here prevents Make from
# erroring with "no rule to make target X" when they appear after the
# preset name. Keep in sync with the services defined under compose/*.yml.
.PHONY: workspace mysql postgres postgres-postgis mongo redis etcd etcd-manager \
        dtm kafka kafka-ui rabbitmq elasticsearch minio grafana prometheus \
        jaeger traefik gitlab gitlab-runner portainer swagger-editor swagger-ui

#--------------------------------------------------------------------------
# General
#--------------------------------------------------------------------------

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

init: ## Initialize project: copy .env.example to .env, create data directory
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@test -d ~/codes || mkdir -p ~/codes && echo "Created ~/codes"
	@mkdir -p $(DATA_PATH_HOST)
	@echo "Initialization complete. Review .env before starting services."

build-base: ## Build the workspace-base image
	$(COMPOSE) build workspace

config: ## Validate and print docker compose configuration
	$(COMPOSE) $(COMPOSE_FILES) config

up: ## Start workspace only
	$(COMPOSE) up -d workspace

shell: ## Enter workspace shell (zsh)
	$(COMPOSE) exec workspace zsh

down: ## Stop and remove all services
	$(COMPOSE) $(COMPOSE_FILES) down

ps: ## List running containers
	$(COMPOSE) $(COMPOSE_FILES) ps

logs: ## Follow logs for all services
	$(COMPOSE) $(COMPOSE_FILES) logs -f

#--------------------------------------------------------------------------
# Infrastructure Profiles (modular compose files)
#--------------------------------------------------------------------------

db: ## Start database services (MySQL, Postgres, Mongo, PostGIS)
	$(COMPOSE) -f docker-compose.yml -f compose/db.yml up -d

cache: ## Start cache services (Redis)
	$(COMPOSE) -f docker-compose.yml -f compose/cache.yml up -d

mq: ## Start message queue services (RabbitMQ, Kafka)
	$(COMPOSE) -f docker-compose.yml -f compose/mq.yml up -d

storage: ## Start storage services (MinIO)
	$(COMPOSE) -f docker-compose.yml -f compose/storage.yml up -d

registry: ## Start registry/coordination services (etcd, DTM)
	$(COMPOSE) -f docker-compose.yml -f compose/registry.yml up -d

observability: ## Start observability stack (ELK, Grafana, Prometheus, Jaeger)
	$(COMPOSE) -f docker-compose.yml -f compose/observability.yml up -d

ci: ## Start CI/management services (GitLab, Portainer) - requires Postgres + Redis
	$(COMPOSE) -f docker-compose.yml -f compose/db.yml -f compose/cache.yml -f compose/ci.yml up -d

gateway: ## Start gateway (Traefik) - dashboard only, services on host ports
	$(COMPOSE) -f docker-compose.yml -f compose/gateway.yml up -d

# Traefik opt-in 路由（需在 .env 设置 TRAEFIK_ENABLE=true）
# 用法：make gateway-routed PROFILES="mysql redis kafka"
gateway-routed: ## Start Traefik with service routing enabled (set TRAEFIK_ENABLE=true first)
	@test "$$TRAEFIK_ENABLE" = "true" || (echo "❌ TRAEFIK_ENABLE must be set to 'true' in .env" && exit 1)
	$(COMPOSE) -f docker-compose.yml -f compose/gateway.yml --profile $(PROFILES) up -d

docs: ## Start API documentation tools (Swagger)
	$(COMPOSE) -f docker-compose.yml -f compose/docs.yml up -d

#--------------------------------------------------------------------------
# Preset Environments for Multi-Language Development
#--------------------------------------------------------------------------
#
# Each preset has a default service list (see scripts/dev-up.sh). Override
# the default by listing services directly on the command line, e.g.:
#
#   make rust-env                                  # default services
#   make rust-env workspace mysql postgres redis    # custom subset
#   make go-env                                    # Go default
#   make dev mysql redis kafka                     # ad-hoc (no preset)
#   make full-env                                  # everything
#
# Available services: workspace, mysql, postgres, mongo, redis, etcd,
# etcd-manager, dtm, kafka, kafka-ui, rabbitmq, elasticsearch, minio,
# grafana, prometheus, jaeger, traefik, gitlab, swagger-editor, swagger-ui.

go-env: ## Go preset. Usage: make go-env [svc1 svc2 ...]
	@./scripts/dev-up.sh $@ $(filter-out $@,$(MAKECMDGOALS))

rust-env: ## Rust preset. Usage: make rust-env [svc1 svc2 ...]
	@./scripts/dev-up.sh $@ $(filter-out $@,$(MAKECMDGOALS))

php-env: ## PHP preset. Usage: make php-env [svc1 svc2 ...]
	@./scripts/dev-up.sh $@ $(filter-out $@,$(MAKECMDGOALS))

full-env: ## Start everything, or: make full-env [svc1 svc2 ...]
	@./scripts/dev-up.sh $@ $(filter-out $@,$(MAKECMDGOALS))

dev: ## Ad-hoc services: make dev svc1 [svc2 ...] (no preset default)
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make dev <service1> [service2] ..."; \
		exit 1; \
	fi
	@./scripts/dev-up.sh custom $(filter-out $@,$(MAKECMDGOALS))

#--------------------------------------------------------------------------
# Utility
#--------------------------------------------------------------------------

check: ## Pre-flight check: verify all images reachable on configured mirrors
	@./scripts/check-versions.sh

lock: ## Lock current running image versions to .env.lock for reproducibility
	@bash scripts/lock-versions.sh
