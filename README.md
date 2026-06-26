# pf-db

Centralized PostgreSQL schema and Alembic migrations for the pf ecosystem.

## Overview

`pf-db` is the single source of truth for the database shared by `pf-payroll` and `pf-rates`.
It owns DDL, migrations, and seeds. It has no application code.

```
pf-payroll ──┐
              ├── PostgreSQL (pf-db) ◄── Alembic migrations (this repo)
pf-rates   ──┘
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
| `make db-up` | Start postgres container |
| `make db-down` | Stop container |
| `make db-reset` | Destroy volume and restart (**destroys data**) |
| `make schema-apply` | Apply idempotent DDL via `docker exec` (local only) |
| `make seed-base` | Load base seed data |
| `make seed-test` | Load base + test fixtures |
| `make migrate` | `alembic upgrade head` (CI / Cloud Run) |
| `make rollback` | `alembic downgrade -1` |
| `make stamp` | Stamp existing DB at head without re-running migrations |
| `make check` | Lint + migration-check |

## Tables

17 tables across two domains:

**Financial rates** (read/written by `pf-rates`):
`currencies` · `exchange_rates` · `economic_indices` · `income_tax_brackets`

**Payroll** (read/written by `pf-payroll`):
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
Each consuming service uses its own env-var prefix (`PAYROLL_DATABASE_URL`, `FINANCIAL_DATA_DATABASE_URL`).

## CI

Every PR runs: `alembic upgrade head` → `alembic check` against a fresh postgres:16 container.

## Related repositories

- [`pf-payroll`](../pf-payroll) — Chilean payroll simulation and tax calculation
- [`pf-rates`](../pf-rates) — Chilean financial reference data (UF, UTM, exchange rates)
