-- ============================================================
-- Real / production-like seed data.
-- Applied via: make seed-real  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Pension plans — one plan per AFP with real commission rates
-- ============================================================
INSERT INTO pension_plans (institution_id, valid_from, valid_to, additional_rate)
SELECT pi.id, DATE '2024-11-01', NULL, 0.0116
FROM pension_institutions pi
WHERE pi.code = 'AFP_PLANVITAL'
  AND NOT EXISTS (
      SELECT 1
      FROM pension_plans pp
      WHERE pp.institution_id = pi.id
        AND pp.valid_from     = DATE '2024-11-01'
  );

-- ============================================================
-- 2. Health plans
-- ============================================================
INSERT INTO health_plans (institution_id, valid_from, valid_to, plan_name, contracted_uf)
SELECT hi.id, entry.valid_from, entry.valid_to, entry.plan_name, entry.contracted_uf
FROM health_institutions hi
CROSS JOIN (VALUES
    (DATE '2024-11-01', NULL::DATE, 'Base',        5.42::NUMERIC(10,4)),
    (DATE '2024-11-01', NULL::DATE, 'GES',         0.91::NUMERIC(10,4)),
    (DATE '2024-11-01', NULL::DATE, 'Adicionales', 0.79::NUMERIC(10,4))
) AS entry(valid_from, valid_to, plan_name, contracted_uf)
WHERE hi.code = 'ESENCIAL'
  AND NOT EXISTS (
      SELECT 1
      FROM health_plans hp
      WHERE hp.institution_id = hi.id
        AND hp.valid_from     = entry.valid_from
        AND COALESCE(hp.plan_name, '') = entry.plan_name
  );

-- ============================================================
-- 3. Contribution caps
-- ============================================================
INSERT INTO contribution_caps (cap_type, valid_from, valid_to, value_uf) VALUES
    ('pension_health', DATE '2024-01-01', DATE '2024-12-31', 84.3000),
    ('pension_health', DATE '2025-01-01', DATE '2025-12-31', 87.8000),
    ('pension_health', DATE '2026-01-01', DATE '2026-01-31', 89.9000),
    ('pension_health', DATE '2026-02-01', NULL, 90.0000)
ON CONFLICT (cap_type, valid_from) DO UPDATE
SET
    valid_to = EXCLUDED.valid_to,
    value_uf = EXCLUDED.value_uf;

-- ============================================================
-- 4. Employers
-- ============================================================

INSERT INTO employers (
    name,
    tax_id,
    country_code,
    started_at,
    payment_date_rule,
    payment_month_offset,
    payment_day_of_month,
    payment_business_day_offset,
    payment_calendar_day_offset,
    payment_effective_on_processing_next_day,
    payment_fixed_day_roll,
    first_increase_period_year,
    first_increase_period_month,
    increase_frequency
) VALUES
    (
        'DALT-CONSULTORES',
        '52.005.257-7',
        'CL',
        DATE '2016-07-18',
        'last_business_day_of_month',
        0,
        NULL,
        0,
        0,
        FALSE,
        'previous_business_day',
        NULL,
        NULL,
        NULL
    ),
    (
        'CLINICA-ALEMANA',
        '77.413.290-2',
        'CL',
        DATE '2018-04-03',
        'calendar_days_before_end_of_month',
        0,
        NULL,
        0,
        7,
        TRUE,
        'previous_business_day',
        NULL,
        NULL,
        6
    ),
    (
        'WALMART-CHILE',
        '76.042.014-K',
        'CL',
        DATE '2024-11-18',
        'last_business_day_of_month',
        0,
        NULL,
        1,
        0,
        TRUE,
        'previous_business_day',
        2026,
        5,
        NULL
    )
ON CONFLICT (name) DO UPDATE
SET
    tax_id = EXCLUDED.tax_id,
    country_code = EXCLUDED.country_code,
    started_at = EXCLUDED.started_at,
    payment_date_rule = EXCLUDED.payment_date_rule,
    payment_month_offset = EXCLUDED.payment_month_offset,
    payment_day_of_month = EXCLUDED.payment_day_of_month,
    payment_business_day_offset = EXCLUDED.payment_business_day_offset,
    payment_calendar_day_offset = EXCLUDED.payment_calendar_day_offset,
    payment_effective_on_processing_next_day = EXCLUDED.payment_effective_on_processing_next_day,
    payment_fixed_day_roll = EXCLUDED.payment_fixed_day_roll;

-- ============================================================
-- 5. Complementary insurance providers
-- ============================================================
INSERT INTO complementary_insurance_providers (name) VALUES
    ('METLIFE')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 6. Complementary insurance plans
-- ============================================================
INSERT INTO complementary_insurance_plans (
    provider_id,
    name,
    cost_type,
    cost_value,
    cost_currency,
    valid_from,
    valid_to
)
SELECT
    p.id,
    entry.name,
    entry.cost_type::complementary_insurance_cost_type,
    entry.cost_value,
    entry.cost_currency,
    entry.valid_from,
    entry.valid_to
FROM complementary_insurance_providers p
CROSS JOIN (VALUES
    ('SEGURO DENTAL - PLAN AVANZADO',    'fixed_uf', 0.19::NUMERIC(12,4), 'UF', DATE '2025-02-01', NULL::DATE),
    ('SEGURO DE SALUD - PLAN DESTACADO', 'fixed_uf', 0.25::NUMERIC(12,4), 'UF', DATE '2025-01-01', DATE '2025-01-01'),
    ('SEGURO DE SALUD - PLAN DESTACADO', 'fixed_uf', 0.83::NUMERIC(12,4), 'UF', DATE '2025-02-01', NULL::DATE),
    ('SEGURO CATASTROFICO - PLAN AVANZADO', 'fixed_uf', 0.13::NUMERIC(12,4), 'UF', DATE '2025-02-01', NULL::DATE)
) AS entry(name, cost_type, cost_value, cost_currency, valid_from, valid_to)
WHERE p.name = 'METLIFE'
  AND NOT EXISTS (
      SELECT 1
      FROM complementary_insurance_plans cp
      WHERE cp.provider_id = p.id
        AND cp.name        = entry.name
        AND cp.valid_from  = entry.valid_from
  );