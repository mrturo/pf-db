.DEFAULT_GOAL := help
SHELL         := /bin/bash

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# Load .env if it exists (for local use; CI sets DATABASE_URL directly)
ifneq (,$(wildcard .env))
    include .env
    export
endif

# DB container name (from docker-compose service "db")
DB_CONTAINER  := pf-db-db-1
DB_NAME       := pf
DB_USER       := pf
ADMINER_PORT  ?= 8080

# PostgreSQL connection string for psql targets (strips asyncpg driver prefix)
PSQL_URL := $(subst postgresql+asyncpg://,postgresql://,$(DATABASE_URL))

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------
.PHONY: db-up
db-up: ## Start the PostgreSQL container (idempotent)
	docker compose up -d db
	@echo "Waiting for PostgreSQL to be ready..."
	@docker compose exec db sh -c 'until pg_isready -U $(DB_USER) -d $(DB_NAME); do sleep 1; done'

.PHONY: db-down
db-down: ## Stop and remove the PostgreSQL container
	docker compose down

.PHONY: db-reset
db-reset: ## Destroy volume and restart fresh (DESTROYS ALL DATA)
	docker compose down -v
	$(MAKE) db-up

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
.PHONY: install
install: ## Install Python dependencies into the active virtualenv
	pip install -e ".[dev]"

.PHONY: env-write
env-write: ## Write .env from .env.example (does not overwrite existing)
	@test -f .env && echo ".env already exists" || (cp .env.example .env && echo ".env written")

# ---------------------------------------------------------------------------
# Schema (local — applies SQL directly via docker exec)
# ---------------------------------------------------------------------------
.PHONY: schema-apply
schema-apply: ## Apply combined DDL schema via docker exec (local dev only)
	docker compose exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/01_schema.sql
	@echo "Schema applied."

# ---------------------------------------------------------------------------
# Migrations (Alembic — for CI and production Cloud Run Job)
# ---------------------------------------------------------------------------
.PHONY: migrate
migrate: ## Apply all pending Alembic migrations (requires direct DB access)
	alembic upgrade head

.PHONY: rollback
rollback: ## Roll back the last applied migration
	alembic downgrade -1

.PHONY: migration-check
migration-check: ## Fail if there are pending migration files without a DB version (CI)
	alembic check

.PHONY: stamp
stamp: ## Stamp the existing DB at head without re-running migrations
	alembic stamp head

# ---------------------------------------------------------------------------
# Seeds (apply via docker exec — works with Rancher Desktop)
# ---------------------------------------------------------------------------
.PHONY: seed-base
seed-base: ## Load base seed data (safe for all environments)
	docker compose exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/02_seed_base.sql
	@echo "Base seed applied."

.PHONY: seed-test
seed-test: seed-base ## Load test fixtures (runs seed-base first)
	docker compose exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/03_seed_test.sql
	@echo "Test seed applied."

# ---------------------------------------------------------------------------
# Local bootstrap (shortcut: db-up + schema + base seed)
# ---------------------------------------------------------------------------
.PHONY: local-up
local-up: db-up schema-apply seed-base ## Full local bootstrap: start DB, apply schema, load base seed

.PHONY: local-up-test
local-up-test: db-up schema-apply seed-test ## Full local bootstrap with test fixtures

# ---------------------------------------------------------------------------
# Adminer
# ---------------------------------------------------------------------------
.PHONY: adminer-up
adminer-up: db-up ## Start Adminer (starts DB first)
	docker compose up -d adminer
	@echo "Adminer → http://localhost:$(ADMINER_PORT)"

.PHONY: adminer-down
adminer-down: ## Stop and remove the Adminer container
	docker compose rm -sf adminer

.PHONY: adminer-restart
adminer-restart: ## Restart Adminer without touching the DB
	docker compose rm -sf adminer
	docker compose up -d adminer
	@echo "Adminer → http://localhost:$(ADMINER_PORT)"

# ---------------------------------------------------------------------------
# Quality
# ---------------------------------------------------------------------------
.PHONY: lint
lint: ## Run ruff linter over alembic/
	ruff check alembic/

.PHONY: check
check: lint ## Run all quality checks (lint only for local; CI also runs migration-check)
