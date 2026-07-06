"""Create payroll schema (reference data, payroll core, analytics view).

Revision ID: 0002
Revises: 0001
Create Date: 2026-06-25
"""

from alembic import op

revision: str = "0002"
down_revision: str = "0001"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Create all payroll tables and types."""
    # ------------------------------------------------------------------ #
    # Custom enum types                                                    #
    # ------------------------------------------------------------------ #
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE health_institution_kind AS ENUM ('fonasa', 'isapre');
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE contribution_cap_type AS ENUM ('pension_health', 'unemployment');
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE complementary_insurance_cost_type
                AS ENUM ('fixed_clp', 'fixed_uf', 'variable_percentage');
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE payroll_status AS ENUM ('projected', 'actual', 'reviewed');
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE employment_contract_kind AS ENUM ('indefinite', 'fixed_term');
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE employer_payment_date_rule AS ENUM (
                'last_business_day_of_month',
                'fixed_day_of_month',
                'calendar_days_before_end_of_month'
            );
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE employer_fixed_day_roll
                AS ENUM ('previous_business_day', 'next_business_day');
        EXCEPTION WHEN duplicate_object THEN null;
        END $$
    """)

    # ------------------------------------------------------------------ #
    # Reference data: pension & health institutions                        #
    # ------------------------------------------------------------------ #
    op.execute("""
        CREATE TABLE IF NOT EXISTS pension_institutions (
            id             BIGSERIAL    PRIMARY KEY,
            code           VARCHAR(40)  NOT NULL UNIQUE,
            name           VARCHAR(120) NOT NULL,
            mandatory_rate NUMERIC(6,4) NOT NULL DEFAULT 0.10,
            is_active      BOOLEAN      NOT NULL DEFAULT TRUE
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS health_institutions (
            id             BIGSERIAL               PRIMARY KEY,
            code           VARCHAR(40)             NOT NULL UNIQUE,
            name           VARCHAR(120)            NOT NULL,
            kind           health_institution_kind NOT NULL,
            mandatory_rate NUMERIC(6,4)            NOT NULL DEFAULT 0.07,
            is_active      BOOLEAN                 NOT NULL DEFAULT TRUE
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS pension_plans (
            id              BIGSERIAL    PRIMARY KEY,
            institution_id  BIGINT       NOT NULL REFERENCES pension_institutions(id),
            valid_from      DATE         NOT NULL,
            valid_to        DATE,
            additional_rate NUMERIC(6,4) NOT NULL DEFAULT 0 CHECK (additional_rate >= 0),
            CONSTRAINT chk_pension_plan_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS health_plans (
            id             BIGSERIAL     PRIMARY KEY,
            institution_id BIGINT        NOT NULL REFERENCES health_institutions(id),
            valid_from     DATE          NOT NULL,
            valid_to       DATE,
            plan_name      VARCHAR(120),
            contracted_uf  NUMERIC(10,4) NOT NULL DEFAULT 0 CHECK (contracted_uf >= 0),
            CONSTRAINT chk_health_plan_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS contribution_caps (
            id         BIGSERIAL             PRIMARY KEY,
            cap_type   contribution_cap_type NOT NULL,
            valid_from DATE                  NOT NULL,
            valid_to   DATE,
            value_uf   NUMERIC(10,4)         NOT NULL CHECK (value_uf > 0),
            UNIQUE (cap_type, valid_from)
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS complementary_insurance_providers (
            id   BIGSERIAL    PRIMARY KEY,
            name VARCHAR(120) NOT NULL UNIQUE
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS complementary_insurance_plans (
            id            BIGSERIAL                         PRIMARY KEY,
            provider_id   BIGINT                            NOT NULL
                REFERENCES complementary_insurance_providers(id),
            name          VARCHAR(120)                      NOT NULL,
            cost_type     complementary_insurance_cost_type NOT NULL,
            cost_value    NUMERIC(12,4)                     NOT NULL CHECK (cost_value >= 0),
            cost_currency CHAR(3)                           NOT NULL DEFAULT 'CLP',
            valid_from    DATE                              NOT NULL,
            valid_to      DATE,
            CONSTRAINT chk_complementary_plan_dates
                CHECK (valid_to IS NULL OR valid_to >= valid_from)
        )
    """)

    # ------------------------------------------------------------------ #
    # Payroll core                                                         #
    # ------------------------------------------------------------------ #
    op.execute("""
        CREATE TABLE IF NOT EXISTS employers (
            id                                       BIGSERIAL                  PRIMARY KEY,
            name                                     VARCHAR(120)               NOT NULL UNIQUE,
            tax_id                                   VARCHAR(32),
            country_code                             CHAR(2)                    NOT NULL
                DEFAULT 'CL',
            started_at                               DATE                       NOT NULL,
            ended_at                                 DATE,
            first_increase_period_year               SMALLINT
                CHECK (first_increase_period_year BETWEEN 1990 AND 2100),
            first_increase_period_month              SMALLINT
                CHECK (first_increase_period_month BETWEEN 1 AND 12),
            increase_frequency                       SMALLINT
                CHECK (increase_frequency > 0),
            payment_date_rule                        employer_payment_date_rule NOT NULL
                DEFAULT 'last_business_day_of_month',
            payment_month_offset                     SMALLINT                   NOT NULL DEFAULT 0
                CHECK (payment_month_offset >= 0),
            payment_day_of_month                     SMALLINT
                CHECK (payment_day_of_month BETWEEN 1 AND 31),
            payment_business_day_offset              SMALLINT                   NOT NULL DEFAULT 0
                CHECK (payment_business_day_offset >= 0),
            payment_calendar_day_offset              SMALLINT                   NOT NULL DEFAULT 0
                CHECK (payment_calendar_day_offset >= 0),
            payment_effective_on_processing_next_day BOOLEAN                    NOT NULL
                DEFAULT FALSE,
            payment_fixed_day_roll                   employer_fixed_day_roll    NOT NULL
                DEFAULT 'previous_business_day'
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS payroll_periods (
            id                       BIGSERIAL              PRIMARY KEY,
            employer_id              BIGINT                 NOT NULL REFERENCES employers(id),
            period_year              SMALLINT               NOT NULL,
            period_month             SMALLINT               NOT NULL,
            payment_date             DATE                   NOT NULL,
            worked_days              SMALLINT               NOT NULL DEFAULT 30,
            status                   payroll_status         NOT NULL DEFAULT 'projected',
            employment_contract_kind employment_contract_kind NOT NULL DEFAULT 'indefinite',
            declared_net_pay_clp     NUMERIC(18,2),
            expected_net_pay_clp     NUMERIC(18,2),
            net_pay_difference_clp   NUMERIC(18,2),
            pension_plan_id          BIGINT                 REFERENCES pension_plans(id),
            UNIQUE (employer_id, period_year, period_month)
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS payroll_period_health_plans (
            period_id      BIGINT NOT NULL REFERENCES payroll_periods(id) ON DELETE CASCADE,
            health_plan_id BIGINT NOT NULL REFERENCES health_plans(id),
            PRIMARY KEY (period_id, health_plan_id)
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS payroll_complementary_insurance (
            period_id                       BIGINT NOT NULL
                REFERENCES payroll_periods(id) ON DELETE CASCADE,
            complementary_insurance_plan_id BIGINT NOT NULL
                REFERENCES complementary_insurance_plans(id),
            PRIMARY KEY (period_id, complementary_insurance_plan_id)
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS payroll_concepts (
            id         BIGSERIAL    PRIMARY KEY,
            code       VARCHAR(40)  NOT NULL UNIQUE,
            name       VARCHAR(120) NOT NULL,
            kind       VARCHAR(20)  NOT NULL CHECK (kind IN ('income', 'discount')),
            is_taxable BOOLEAN      NOT NULL DEFAULT FALSE
        )
    """)

    op.execute("""
        CREATE TABLE IF NOT EXISTS payroll_items (
            id         BIGSERIAL     PRIMARY KEY,
            period_id  BIGINT        NOT NULL REFERENCES payroll_periods(id) ON DELETE CASCADE,
            concept_id BIGINT        NOT NULL REFERENCES payroll_concepts(id),
            amount_clp NUMERIC(18,2) NOT NULL,
            notes      TEXT,
            created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW()
        )
    """)

    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_payroll_items_period_id ON payroll_items(period_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_payroll_items_concept_id ON payroll_items(concept_id)"
    )

    # ------------------------------------------------------------------ #
    # Analytics materialized view                                          #
    # ------------------------------------------------------------------ #
    op.execute("""
        CREATE MATERIALIZED VIEW IF NOT EXISTS mv_payroll_summary AS
        SELECT
            p.id            AS period_id,
            p.employer_id,
            p.period_year,
            p.period_month,
            p.payment_date,
            SUM(CASE WHEN c.kind = 'income' AND c.is_taxable THEN i.amount_clp ELSE 0 END)
                AS taxable_income_clp,
            SUM(CASE WHEN c.kind = 'income'   THEN i.amount_clp ELSE 0 END) AS gross_income_clp,
            SUM(CASE WHEN c.kind = 'discount' THEN i.amount_clp ELSE 0 END) AS total_discounts_clp,
            SUM(CASE WHEN c.kind = 'income'   THEN i.amount_clp ELSE 0 END) -
            SUM(CASE WHEN c.kind = 'discount' THEN i.amount_clp ELSE 0 END) AS net_pay_clp
        FROM payroll_periods p
        JOIN payroll_items   i ON i.period_id  = p.id
        JOIN payroll_concepts c ON c.id = i.concept_id
        GROUP BY p.id
    """)


def downgrade() -> None:
    """Drop all payroll tables, types, and views."""
    op.execute("DROP MATERIALIZED VIEW IF EXISTS mv_payroll_summary")

    op.execute("DROP INDEX IF EXISTS idx_payroll_items_concept_id")
    op.execute("DROP INDEX IF EXISTS idx_payroll_items_period_id")

    op.execute("DROP TABLE IF EXISTS payroll_items")
    op.execute("DROP TABLE IF EXISTS payroll_concepts")
    op.execute("DROP TABLE IF EXISTS payroll_complementary_insurance")
    op.execute("DROP TABLE IF EXISTS payroll_period_health_plans")
    op.execute("DROP TABLE IF EXISTS payroll_periods")
    op.execute("DROP TABLE IF EXISTS employers")
    op.execute("DROP TABLE IF EXISTS complementary_insurance_plans")
    op.execute("DROP TABLE IF EXISTS complementary_insurance_providers")
    op.execute("DROP TABLE IF EXISTS contribution_caps")
    op.execute("DROP TABLE IF EXISTS health_plans")
    op.execute("DROP TABLE IF EXISTS pension_plans")
    op.execute("DROP TABLE IF EXISTS health_institutions")
    op.execute("DROP TABLE IF EXISTS pension_institutions")

    op.execute("DROP TYPE IF EXISTS employer_fixed_day_roll")
    op.execute("DROP TYPE IF EXISTS employer_payment_date_rule")
    op.execute("DROP TYPE IF EXISTS employment_contract_kind")
    op.execute("DROP TYPE IF EXISTS payroll_status")
    op.execute("DROP TYPE IF EXISTS complementary_insurance_cost_type")
    op.execute("DROP TYPE IF EXISTS contribution_cap_type")
    op.execute("DROP TYPE IF EXISTS health_institution_kind")
