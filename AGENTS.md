# AGENTS.md — pf-db

PostgreSQL schema and Alembic migrations for the PF (Personal Finances) ecosystem. **This repo owns DDL and migrations only** — no application code, no HTTP API, no ORM models.

## Purpose

`pf-db` is the single source of truth for all PostgreSQL database objects shared across the PF ecosystem microservices. All consuming microservices connect to the same PostgreSQL instance; each microservice keeps its own SQLAlchemy models and repositories.

```
pf-db/
├── alembic/
│   ├── env.py                     # async runner; reads DATABASE_URL from .env
│   └── versions/
│       ├── 0001_rates_schema.py   # currencies, exchange_rates, economic_indices, income_tax_brackets
│       └── 0002_payroll_schema.py # pension/health/contribution tables + employers + payroll core + mv
├── db/
│   ├── 01_schema.sql              # idempotent DDL reference (do NOT run in production)
│   ├── 02_seed_base.sql           # base seed: currencies, institutions, caps, brackets, concepts
│   ├── 03_seed_test.sql           # test fixtures: plans, insurance providers/plans
│   └── 04_seed_real.sql           # production-realistic data
├── alembic.ini
├── docker-compose.yml             # postgres:16, port ${PF_DB_PORT:-5432}
├── Makefile
└── pyproject.toml
```

## Table ownership

| Tables | Domain |
|---|---|
| `currencies`, `exchange_rates`, `economic_indices`, `income_tax_brackets` | financial rates |
| All others (17 tables total) + `mv_payroll_summary` | payroll |

Ownership means: only the microservices that own a domain write to those tables.
Any microservice may read any table.

## Development commands

See [Commands](README.md#commands) in README.md for the full list of `make` targets.

Run from an activated virtualenv: `source .venv/bin/activate && make <target>`
or: `PATH=.venv/bin:$PATH make <target>`.

## Environment variables

See [Connection](README.md#connection) in README.md for the default `DATABASE_URL`.

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://pf:pf@localhost:5432/pf` | Connection for Alembic and seed targets |
| `PF_DB_PORT` | `5432` | Host port exposed by docker-compose |
| `PIP_ARTIFACTORY` | *(unset)* | Pip index URL for `make install`/`reinstall`; set to Walmart Artifactory URL when on VPN |

**During migration coexistence** (while the old per-project containers are still running),
set in your local `.env`:
```
PF_DB_PORT=5434
DATABASE_URL=postgresql+asyncpg://pf_db:pf_db@localhost:5434/pf_db
```
Remove once the old containers are stopped.

## Local vs production schema application

| Context | Method |
|---|---|
| Local dev | `make schema-apply` (runs `db/01_schema.sql` via `docker exec psql`) |
| CI | `make migrate` → `alembic upgrade head` (requires DB access) |
| Production (Cloud Run) | Cloud Run Job: `alembic upgrade head` from the pf-db image |

The `db/01_schema.sql` file is **idempotent DDL** for human reference and local bootstrapping.
Alembic migration files are the **authoritative source of truth** for production and CI.

## Adding a migration

1. Write the new version file in `alembic/versions/` following the `NNNN_description.py` convention.
2. Set `revision` and `down_revision` correctly.
3. Write `upgrade()` and `downgrade()` using raw SQL via `op.execute()`.
4. Run `make migrate` to apply and `make rollback` to verify the downgrade path.
5. Run `make check` — must pass clean.
6. Commit. CI runs `alembic upgrade head` + `alembic check` on every PR.

## Invariants (never violate)

1. **Migrations before traffic** — any Cloud Run deployment that consumes this DB must run
   `alembic upgrade head` before serving traffic. The Cloud Run Job pattern is the reference.
2. **No application code** — this repo has no `src/`, no FastAPI routes, no business logic.
   ORM models live in the consuming microservices.
3. **No autogenerate** — `target_metadata = None` in `alembic/env.py`. Migrations are hand-written raw SQL.
4. **Idempotent seeds** — all `INSERT` statements in `db/02_seed_base.sql` use `ON CONFLICT DO UPDATE`
   or `ON CONFLICT DO NOTHING`. Running seeds multiple times must be safe.
5. **No float columns** — all monetary/rate columns use `NUMERIC`. Never `FLOAT`.
6. **Schema-apply is local only** — `db/01_schema.sql` is never applied in CI or production.
   Alembic is the production path.

## Production cutover (from per-service DBs)

When retiring old per-service databases:

```bash
# 1. Dump payroll data only (exclude rates tables + alembic_version)
pg_dump --data-only \
  --exclude-table=currencies --exclude-table=exchange_rates \
  --exclude-table=economic_indices --exclude-table=income_tax_brackets \
  --exclude-table=alembic_version \
  $OLD_PAYROLL_DB_URL > payroll_data_only.sql

# 2. Apply pf-db migrations to the target DB
DATABASE_URL=$PF_DB_URL alembic upgrade head

# 3. Restore payroll data
psql $PF_DB_URL < payroll_data_only.sql

# 4. Refresh the materialized view
psql $PF_DB_URL -c "REFRESH MATERIALIZED VIEW mv_payroll_summary;"

# 5. Update both Cloud Run services to point at the new DATABASE_URL
# 6. Retire the old containers/instances
```

Rates data (`exchange_rates`, `economic_indices`) is re-fetchable via provider APIs — no dump needed.

## CI

See [CI](README.md#ci) in README.md. A manual approval gate is required before migrations execute.

## Versioning

- Conventional Commits (English)
- Never autonomously commit, push branches, or open PRs — requires explicit user command
