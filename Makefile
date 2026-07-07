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

# DB container name (from compose service "db")
DB_CONTAINER  := pf-db-1
DB_NAME       := pf_db
DB_USER       := pf_db
ADMINER_PORT  ?= 8080
# QEMU monitor socket path (Rancher Desktop / Lima on macOS)
QMP_SOCK      ?= $(HOME)/Library/Application Support/rancher-desktop/lima/0/qmp.sock
# Lima SSH config (Rancher Desktop)
LIMA_DIR      ?= $(HOME)/Library/Application Support/rancher-desktop/lima
LIMA_KEY      ?= $(LIMA_DIR)/_config/user
LIMA_YAML     ?= $(LIMA_DIR)/0/lima.yaml

# Auto-detect container CLI: prefer nerdctl (containerd) over docker (moby).
# On macOS Rancher Desktop, nerdctl forwards ports to localhost; moby does not.
# Override with: make NERDCTL=docker <target>
NERDCTL ?= $(shell \
  if nerdctl info >/dev/null 2>&1; then \
    echo nerdctl; \
  elif $$HOME/.rd/bin/nerdctl info >/dev/null 2>&1; then \
    echo $$HOME/.rd/bin/nerdctl; \
  elif $$HOME/.rd/bin/nerdctl --address /var/run/docker/containerd/containerd.sock info >/dev/null 2>&1; then \
    echo "$$HOME/.rd/bin/nerdctl --address /var/run/docker/containerd/containerd.sock"; \
  else \
    echo docker; \
  fi)
COMPOSE := $(NERDCTL) compose

# Finds first free host port for Adminer by querying the active runtime for
# allocated ports, then verifying with socket bind.
_find_adminer_port = python3 -c $$'import subprocess,socket,shlex\ndef ps(cmd):\n  return subprocess.run(cmd,capture_output=True,text=True).stdout\nout=ps(shlex.split("$(NERDCTL)")+["ps","--format","{{.Ports}}"])+ps(["docker","ps","--format","{{.Ports}}"])\nused={int(x.split("->")[0].split(":")[-1]) for ln in out.splitlines() for x in ln.split(",") if "->" in x and ":" in x.split("->")[0]}\nfor p in range($(ADMINER_PORT),$(ADMINER_PORT)+200):\n  if p in used:continue\n  s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)\n  try:\n    s.bind(("127.0.0.1",p));s.close();print(p);break\n  except OSError:\n    s.close()'

# PostgreSQL connection string for psql targets (strips asyncpg driver prefix)
PSQL_URL := $(subst postgresql+asyncpg://,postgresql://,$(DATABASE_URL))

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------
.PHONY: db-up
db-up: ## Start the PostgreSQL container (idempotent)
	$(COMPOSE) up -d db
	@echo "Waiting for PostgreSQL to be ready..."
	@$(COMPOSE) exec db sh -c 'until pg_isready -U $(DB_USER) -d $(DB_NAME); do sleep 1; done'
	@$(MAKE) --no-print-directory _fwd_db_port

# Refresh the host→VM port forward for the DB port.
# Prefers Lima SSH (Rancher Desktop): kills any stale tunnel and creates a fresh one.
# Falls back to QMP hostfwd for other QEMU-based setups.
.PHONY: _fwd_db_port
_fwd_db_port:
	@LIMA_KEY="$(LIMA_KEY)"; \
	LIMA_PORT=$$(grep -m1 'localPort:' "$(LIMA_YAML)" 2>/dev/null | tr -d ' ' | cut -d: -f2); \
	if [ -f "$$LIMA_KEY" ] && [ -n "$$LIMA_PORT" ]; then \
	    pkill -f "ssh.*-L $(PF_DB_PORT):127.0.0.1:$(PF_DB_PORT)" 2>/dev/null; \
	    sleep 0.3; \
	    ssh -o ControlMaster=no -o StrictHostKeyChecking=no -o BatchMode=yes \
	        -i "$$LIMA_KEY" -p "$$LIMA_PORT" "$(USER)@127.0.0.1" \
	        -L "$(PF_DB_PORT):127.0.0.1:$(PF_DB_PORT)" -N -f 2>/dev/null || true; \
	    sleep 0.3; \
	else \
	    printf '{"execute":"qmp_capabilities"}\n{"execute":"human-monitor-command","arguments":{"command-line":"hostfwd_add tcp:127.0.0.1:$(PF_DB_PORT)-:$(PF_DB_PORT)"}}\n' \
	        | nc -U "$(QMP_SOCK)" >/dev/null 2>&1 || true; \
	fi

.PHONY: db-down
db-down: ## Stop and remove the PostgreSQL container
	$(COMPOSE) down

.PHONY: db-reset
db-reset: ## Destroy volume and restart fresh (DESTROYS ALL DATA)
	$(COMPOSE) down -v
	$(MAKE) db-up

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
.PHONY: install
install: ## Install Python dependencies (Corporative Artifactory on VPN, PyPI otherwise)
	@_pip_log=$$(mktemp); \
	if [ -n "$(PIP_ARTIFACTORY)" ] && PIP_RETRIES=0 pip install -i "$(PIP_ARTIFACTORY)" -e ".[dev]" >"$$_pip_log" 2>&1; then \
	  cat "$$_pip_log"; \
	else \
	  pip install -e ".[dev]"; \
	fi; \
	rm -f "$$_pip_log"

.PHONY: reinstall
reinstall: clean install ## Wipe caches and reinstall all dependencies (Corporative Artifactory on VPN, PyPI otherwise)

.PHONY: clean
clean: ## Remove build artifacts and caches
	rm -rf .ruff_cache build dist
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
	find . -type d -name "*.egg-info" -prune -exec rm -rf {} +

.PHONY: env-write
env-write: ## Write .env from .env.example (does not overwrite existing)
	@test -f .env && echo ".env already exists" || (cp .env.example .env && echo ".env written")

# ---------------------------------------------------------------------------
# Schema (local — applies SQL directly via docker exec)
# ---------------------------------------------------------------------------
.PHONY: schema-apply
schema-apply: ## Apply combined DDL schema via docker exec (local dev only)
	$(COMPOSE) exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/01_schema.sql
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
migration-check: ## Fail if the DB is not at the latest migration head (CI)
	@alembic current 2>&1 | grep -q "(head)" || { echo "ERROR: DB is not at migration head"; exit 1; }

.PHONY: stamp
stamp: ## Stamp the existing DB at head without re-running migrations
	alembic stamp head

# ---------------------------------------------------------------------------
# Seeds (apply via docker exec — works with Rancher Desktop)
# ---------------------------------------------------------------------------
.PHONY: seed-base
seed-base: ## Load base seed data (safe for all environments)
	$(COMPOSE) exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/02_seed_base.sql
	@echo "Base seed applied."

.PHONY: seed-test
seed-test: seed-base ## Load test fixtures (runs seed-base first)
	$(COMPOSE) exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/03_seed_test.sql
	@echo "Test seed applied."

.PHONY: seed-real
seed-real: seed-base ## Load production-realistic data (runs seed-base first)
	$(COMPOSE) exec -T db psql -U $(DB_USER) -d $(DB_NAME) -f /dev/stdin < db/04_seed_real.sql
	@echo "Real seed applied."

# ---------------------------------------------------------------------------
# Local bootstrap (shortcut: db-up + schema + base seed)
# ---------------------------------------------------------------------------
.PHONY: local-up
local-up: db-up schema-apply seed-base ## Full local bootstrap: start DB, apply schema, load base seed

.PHONY: local-up-test
local-up-test: db-up schema-apply seed-test ## Full local bootstrap with test fixtures

.PHONY: local-up-real
local-up-real: db-up migrate seed-real ## Full local bootstrap using Alembic migrations (CI-equivalent)

.PHONY: local-down
local-down: adminer-down db-down ## Tear down the full local stack (DB + Adminer)

.PHONY: local-restart
local-restart: local-down local-up ## Restart local stack with base seed

.PHONY: local-restart-test
local-restart-test: local-down local-up-test ## Restart local stack with test fixtures

.PHONY: local-restart-real
local-restart-real: local-down local-up-real ## Restart local stack using Alembic migrations

# ---------------------------------------------------------------------------
# Adminer
# ---------------------------------------------------------------------------
# Private target: launch the Adminer container (assumes DB network exists).
# Called by adminer-up (after db-up) and adminer-restart (after adminer-down).
.PHONY: _adminer-launch
_adminer-launch:
	@port=$$($(_find_adminer_port)); \
	$(NERDCTL) run -d \
	  --name pf-db-adminer-1 \
	  --network pf-db_default \
	  -p $$port:8080 \
	  -e ADMINER_DEFAULT_SERVER=db \
	  adminer; \
	$(_qmp_hostfwd) $$port $$port | nc -U "$(QMP_SOCK)" >/dev/null 2>&1 || true; \
	echo "Adminer → http://localhost:$$port"

.PHONY: adminer-up
adminer-up: db-up adminer-down _adminer-launch ## Start Adminer (starts DB first; auto-selects a free host port)

.PHONY: adminer-down
adminer-down: ## Stop and remove the Adminer container
	$(NERDCTL) rm -f pf-db-adminer-1 >/dev/null 2>&1 || true

.PHONY: adminer-restart
adminer-restart: adminer-down _adminer-launch ## Restart Adminer without touching the DB (auto-selects a free host port)

# ---------------------------------------------------------------------------
# Quality
# ---------------------------------------------------------------------------
.PHONY: lint
lint: ## Run ruff linter over alembic/
	ruff check alembic/

.PHONY: check
check: lint ## Run all quality checks (lint only for local; CI also runs migration-check)
