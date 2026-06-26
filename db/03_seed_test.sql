-- ============================================================
-- Test-only seed data — non-production fixtures.
-- Applied via: make seed-test  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Pension plans (one base plan per institution)
-- ============================================================
INSERT INTO pension_plans (institution_id, valid_from, valid_to, additional_rate)
SELECT pi.id, DATE '2026-01-01', NULL, 0
FROM pension_institutions pi
WHERE NOT EXISTS (
    SELECT 1
    FROM pension_plans pp
    WHERE pp.institution_id = pi.id
      AND pp.valid_from     = DATE '2026-01-01'
      AND pp.additional_rate = 0
);

-- ============================================================
-- 2. Health plans (one base plan per institution)
-- ============================================================
INSERT INTO health_plans (institution_id, valid_from, valid_to, plan_name, contracted_uf)
SELECT hi.id, DATE '2026-01-01', NULL, 'Base', 0
FROM health_institutions hi
WHERE NOT EXISTS (
    SELECT 1
    FROM health_plans hp
    WHERE hp.institution_id = hi.id
      AND hp.valid_from     = DATE '2026-01-01'
      AND COALESCE(hp.plan_name, '') = 'Base'
      AND hp.contracted_uf  = 0
);

-- ============================================================
-- 3. Complementary insurance providers
-- ============================================================
INSERT INTO complementary_insurance_providers (name) VALUES
    ('SEGUROS CAJA'),
    ('ISANA'),
    ('CONSALUD')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 4. Complementary insurance plans
-- ============================================================
INSERT INTO complementary_insurance_plans (
    provider_id, name, cost_type, cost_value, cost_currency, valid_from, valid_to
) VALUES
    (
        (SELECT id FROM complementary_insurance_providers WHERE name = 'SEGUROS CAJA'),
        'Plan Clínico Plus - Fixed',
        'fixed_clp'::complementary_insurance_cost_type,
        50000, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM complementary_insurance_providers WHERE name = 'SEGUROS CAJA'),
        'Plan Clínico Plus - Variable',
        'variable_percentage'::complementary_insurance_cost_type,
        2.5, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM complementary_insurance_providers WHERE name = 'ISANA'),
        'Plan Integral - Fixed',
        'fixed_clp'::complementary_insurance_cost_type,
        35000, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM complementary_insurance_providers WHERE name = 'ISANA'),
        'Plan Integral - Variable',
        'variable_percentage'::complementary_insurance_cost_type,
        2.0, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM complementary_insurance_providers WHERE name = 'CONSALUD'),
        'Plan Premium - Fixed',
        'fixed_clp'::complementary_insurance_cost_type,
        55000, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM complementary_insurance_providers WHERE name = 'CONSALUD'),
        'Plan Premium - Variable',
        'variable_percentage'::complementary_insurance_cost_type,
        3.0, 'CLP', DATE '2025-01-01', NULL
    );
