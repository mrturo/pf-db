# AGENTS.md — pf-db

PostgreSQL schema and Alembic migrations for the PF (Personal Finances) ecosystem. **This repo owns DDL and migrations only** — no application code, no HTTP API, no ORM models.

## Purpose

`pf-db` is the single source of truth for all database objects shared across PF ecosystem services. All consuming services connect to the same PostgreSQL instance; each service keeps its own SQLAlchemy models and repositories.

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
│   └── 03_seed_test.sql           # test fixtures: plans, insurance providers/plans
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

Ownership means: only the services that own a domain write to those tables.
Any service may read any table.

## Development commands

```bash
make local-up          # db-up + schema-apply + seed-base (full bootstrap)
make local-up-test     # db-up + schema-apply + seed-test (with test fixtures)

make db-up             # start postgres:16 container
make db-down           # stop container
make db-reset          # destroy volume and restart fresh (DESTROYS ALL DATA)

make install           # install Python dependencies into the active virtualenv
make reinstall         # wipe caches and reinstall all dependencies
make clean             # remove build artifacts and caches
make env-write         # write .env from .env.example (does not overwrite existing)

make schema-apply      # apply db/01_schema.sql via docker exec (local dev only)
make seed-base         # load base seeds
make seed-test         # load base + test fixtures

make adminer-up        # start Adminer UI (starts DB first)
make adminer-down      # stop and remove the Adminer container
make adminer-restart   # restart Adminer without touching the DB

make migrate           # alembic upgrade head (requires direct DB access; use in CI/Cloud Run)
make rollback          # alembic downgrade -1
make stamp             # alembic stamp head (mark existing DB without re-running migrations)
make migration-check   # fail if there are pending unapplied migrations (CI gate)

make lint              # ruff check alembic/
make check             # lint (local); CI additionally runs migration-check
```

Run from an activated virtualenv: `source .venv/bin/activate && make <target>`
or: `PATH=.venv/bin:$PATH make <target>`.

## Environment variable

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://pf:pf@localhost:5432/pf` | Connection for Alembic and seed targets |
| `PF_DB_PORT` | `5432` | Host port exposed by docker-compose |

**During migration coexistence** (while the old per-project containers are still running),
set in your local `.env`:
```
PF_DB_PORT=5434
DATABASE_URL=postgresql+asyncpg://pf:pf@localhost:5434/pf
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
   ORM models live in the consuming services.
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

`.github/workflows/ci.yml` runs on every PR and push to `main`:

1. Start `postgres:16` service container
2. `alembic upgrade head` (applies all migrations)
3. `alembic check` (fails if any migration file has no corresponding DB version)

## Versioning

- Conventional Commits (English)
- Never autonomously commit, push branches, or open PRs — requires explicit user command
