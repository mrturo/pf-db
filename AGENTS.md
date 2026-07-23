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

## Consuming microservices

| Microservice | Domain | Connection env var | Repo |
|---|---|---|---|
| `pf-rates` | financial rates | `PF_DATABASE_URL` | `../pf-rates` |
| `pf-payroll` | payroll | `PF_DATABASE_URL` | `../pf-payroll` |

Both services connect to the same PostgreSQL instance managed by this repo.
Each keeps its own SQLAlchemy ORM models and repositories — no ORM code lives here.

## Language policy

- All code, identifiers, comments, docstrings, and migration files: English
- Exception: preserve official Chilean regulatory terms/SQL literals/seed data in original language only when translation alters meaning

## Code style

- ruff: `extend-select = ["D", "E", "W", "UP"]`, `pep257` convention
- Docstrings required for `alembic/env.py` and migration files
- PEPs: 484 (type hints), 498 (f-strings), 621 (pyproject.toml)
- Never use `print` — use alembic logger if needed

## Design principles

- Idempotent migrations: all DDL uses `CREATE ... IF NOT EXISTS` or equivalent patterns
- Idempotent seeds: all `INSERT` use `ON CONFLICT DO UPDATE` or `ON CONFLICT DO NOTHING`
- Hand-written SQL only — no autogenerate (`target_metadata = None`)
- Always provide `downgrade()` — never leave it as `pass`
- Monetary/rate columns: `NUMERIC` only, never `FLOAT`
- Migrations before traffic: Cloud Run Job applies `alembic upgrade head` before services receive requests

## Development commands

See [Commands](README.md#commands) in README.md for the full list of `make` targets.

Run from an activated virtualenv: `source .venv/bin/activate && make <target>`
or: `PATH=.venv/bin:$PATH make <target>`.

## Git hooks

Installed automatically by `make install` via `git config core.hooksPath .githooks`:

| Hook | Runs | Bypass |
|---|---|---|
| `pre-commit` | lint | `git commit --no-verify` |

## Environment variables

See [Connection](README.md#connection) in README.md for the default `DATABASE_URL`.

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://pf_db:pf_db@localhost:5432/pf_db` | Connection for Alembic and seed targets |
| `PF_DB_PORT` | `5432` | Host port exposed by docker-compose |
| `PIP_ARTIFACTORY` | *(unset)* | Pip index URL for `make install`/`reinstall`; set to Corporative Artifactory URL when on VPN |

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

## CI

See [CI](README.md#ci) in README.md. A manual approval gate is required before migrations execute.

## Versioning

- SemVer; Conventional Commits (English)
- Never autonomously commit, push branches, create issues, or open PRs — requires explicit user command