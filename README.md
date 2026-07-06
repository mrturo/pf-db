# pf-db

PostgreSQL schema and Alembic migrations for the PF (Personal Finances) ecosystem.

## Overview

`pf-db` is the single source of truth for the shared PostgreSQL database used across
all PF ecosystem services. It owns DDL, migrations, and seeds. It has no application code.

```
pf-service-a ──┐
pf-service-b ──┼── PostgreSQL (pf-db) ◄── Alembic migrations (this repo)
pf-service-n ──┘
```

## Quick start

```bash
# 1. Clone and install
git clone <repo-url> pf-db
cd pf-db
python -m venv .venv && source .venv/bin/activate
make install

# 2. Copy env and start
cp .env.example .env
make local-up        # starts postgres, applies schema, loads base seed
```

During migration coexistence (while old per-project containers are running on 5432/5433),
set in `.env`:
```
PF_DB_PORT=5434
DATABASE_URL=postgresql+asyncpg://pf:pf@localhost:5434/pf
```

## Commands

| Command | Description |
|---|---|
| `make local-up` | Full bootstrap: start DB + apply schema + load base seed |
| `make local-up-test` | Same as above + test fixtures |
| `make local-up-real` | Bootstrap using Alembic migrations (CI-equivalent) |
| `make local-down` | Tear down the full local stack (DB + Adminer) |
| `make local-restart` | Restart local stack with base seed |
| `make local-restart-test` | Restart local stack with test fixtures |
| `make local-restart-real` | Restart local stack using Alembic migrations |
| `make db-up` | Start postgres container |
| `make db-down` | Stop container |
| `make db-reset` | Destroy volume and restart (**destroys data**) |
| `make schema-apply` | Apply idempotent DDL via `docker exec` (local only) |
| `make seed-base` | Load base seed data |
| `make seed-test` | Load base + test fixtures |
| `make seed-real` | Load production-realistic data (runs seed-base first) |
| `make adminer-up` | Start Adminer UI (starts DB first) |
| `make adminer-down` | Stop and remove the Adminer container |
| `make adminer-restart` | Restart Adminer without touching the DB |
| `make migrate` | `alembic upgrade head` (CI / Cloud Run) |
| `make rollback` | `alembic downgrade -1` |
| `make stamp` | Stamp existing DB at head without re-running migrations |
| `make migration-check` | Fail if there are pending unapplied migrations (CI gate) |
| `make lint` | Run ruff linter over `alembic/` |
| `make check` | Lint + migration-check |
| `make install` | Install Python dependencies into the active virtualenv |
| `make reinstall` | Wipe caches and reinstall all dependencies |
| `make env-write` | Write `.env` from `.env.example` (does not overwrite existing) |
| `make clean` | Remove build artifacts and caches |

## Tables

17 tables across all domains:

**Financial rates**:
`currencies` · `exchange_rates` · `economic_indices` · `income_tax_brackets`

**Payroll**:
`pension_institutions` · `health_institutions` · `pension_plans` · `health_plans` ·
`contribution_caps` · `complementary_insurance_providers` · `complementary_insurance_plans` ·
`employers` · `payroll_periods` · `payroll_period_health_plans` ·
`payroll_complementary_insurance` · `payroll_concepts` · `payroll_items`

**Analytics**: `mv_payroll_summary` (materialized view)

## Connection

```
postgresql+asyncpg://pf:pf@localhost:5432/pf
```

Set via `DATABASE_URL` environment variable (loaded from `.env` by Alembic).
Each consuming service sets its own env-var prefix for the connection string.

## CI

Every PR runs: `alembic upgrade head` → `alembic check` against a fresh postgres:16 container.

