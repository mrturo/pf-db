-- ============================================================
-- Real / production-like seed data.
-- Applied via: make seed-real  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Pension plans — one plan per AFP with real commission rates
-- ============================================================
-- TODO: fill additional_rate with actual AFP commission rates
-- (e.g. from Superintendencia de Pensiones: https://www.spensiones.cl)
-- INSERT INTO pension_plans (institution_id, valid_from, valid_to, additional_rate)
-- SELECT pi.id, DATE 'YYYY-MM-DD', NULL, <rate>
-- FROM pension_institutions pi WHERE pi.code = '<AFP_CODE>'
-- ON CONFLICT (institution_id, valid_from, additional_rate) DO UPDATE
-- SET valid_to = EXCLUDED.valid_to;

-- ============================================================
-- 2. Health plans — FONASA tiers + ISAPRE base plans
-- ============================================================
-- TODO: fill contracted_uf with real plan values
-- INSERT INTO health_plans (institution_id, valid_from, valid_to, plan_name, contracted_uf)
-- VALUES (...)
-- ON CONFLICT (...) DO UPDATE SET ...;

-- ============================================================
-- 3. Complementary insurance providers
-- ============================================================
-- TODO: insert real providers
-- INSERT INTO complementary_insurance_providers (name) VALUES
--     ('...')
-- ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 4. Complementary insurance plans
-- ============================================================
-- TODO: insert real plans with cost_type, cost_value, cost_currency
