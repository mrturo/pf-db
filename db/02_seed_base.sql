-- ============================================================
-- Base seed data — safe for all environments.
-- Applied via: make seed-base
--
-- This file is the authoritative source for all catalog rows.
-- After upserting, rows NOT present in this file are deleted.
-- If a FK-dependent child row references a to-be-deleted row,
-- the entire transaction rolls back with a clear error.
-- ============================================================
BEGIN;

-- ============================================================
-- 1. Currencies and index units
-- ============================================================
INSERT INTO currencies (code, name, is_fiat, unit_kind) VALUES
    ('CLP', 'Peso chileno',              TRUE,  'currency'),
    ('USD', 'US Dollar',                 TRUE,  'currency'),
    ('EUR', 'Euro',                      TRUE,  'currency'),
    ('UF',  'Unidad de Fomento',         FALSE, 'index_unit'),
    ('UTM', 'Unidad Tributaria Mensual', FALSE, 'index_unit')
ON CONFLICT (code) DO UPDATE
SET
    name      = EXCLUDED.name,
    is_fiat   = EXCLUDED.is_fiat,
    unit_kind = EXCLUDED.unit_kind;

DELETE FROM currencies WHERE code NOT IN ('CLP', 'USD', 'EUR', 'UF', 'UTM');

-- ============================================================
-- 2. Pension institutions
-- ============================================================
INSERT INTO pension_institutions (code, name, mandatory_rate, is_active) VALUES
    ('AFP_CAPITAL',  'AFP Capital',  0.10, FALSE),
    ('AFP_CUPRUM',   'AFP Cuprum',   0.10, FALSE),
    ('AFP_HABITAT',  'AFP Habitat',  0.10, FALSE),
    ('AFP_MODELO',   'AFP Modelo',   0.10, FALSE),
    ('AFP_PLANVITAL','AFP PlanVital',0.10, TRUE),
    ('AFP_PROVIDA',  'AFP ProVida',  0.10, FALSE),
    ('AFP_UNO',      'AFP Uno',      0.10, FALSE)
ON CONFLICT (code) DO UPDATE
SET
    name           = EXCLUDED.name,
    mandatory_rate = EXCLUDED.mandatory_rate,
    is_active      = EXCLUDED.is_active;

DELETE FROM pension_institutions WHERE code NOT IN (
    'AFP_CAPITAL', 'AFP_CUPRUM', 'AFP_HABITAT', 'AFP_MODELO',
    'AFP_PLANVITAL', 'AFP_PROVIDA', 'AFP_UNO'
);

-- ============================================================
-- 3. Health institutions
-- ============================================================
INSERT INTO health_institutions (code, name, kind, mandatory_rate, is_active) VALUES
    ('FONASA',       'Fonasa',        'fonasa', 0.07, FALSE),
    ('BANMEDICA',    'Banmedica',     'isapre', 0.07, FALSE),
    ('COLMENA',      'Colmena',       'isapre', 0.07, FALSE),
    ('CONSALUD',     'Consalud',      'isapre', 0.07, FALSE),
    ('CRUZBLANCA',   'CruzBlanca',    'isapre', 0.07, FALSE),
    ('ESENCIAL',     'Esencial',      'isapre', 0.07, TRUE),
    ('NUEVA_MASVIDA','Nueva Masvida', 'isapre', 0.07, FALSE),
    ('VIDA_TRES',    'Vida Tres',     'isapre', 0.07, FALSE)
ON CONFLICT (code) DO UPDATE
SET
    name           = EXCLUDED.name,
    kind           = EXCLUDED.kind,
    mandatory_rate = EXCLUDED.mandatory_rate,
    is_active      = EXCLUDED.is_active;

DELETE FROM health_institutions WHERE code NOT IN (
    'FONASA', 'BANMEDICA', 'COLMENA', 'CONSALUD',
    'CRUZBLANCA', 'ESENCIAL', 'NUEVA_MASVIDA', 'VIDA_TRES'
);

-- ============================================================
-- 4. Contribution caps
-- ============================================================
INSERT INTO contribution_caps (cap_type, valid_from, valid_to, value_uf) VALUES
    ('pension_health', DATE '2018-01-01', NULL, 90.0600),
    ('unemployment',   DATE '2018-01-01', NULL, 135.0900)
ON CONFLICT (cap_type, valid_from) DO UPDATE
SET
    valid_to = EXCLUDED.valid_to,
    value_uf = EXCLUDED.value_uf;

DELETE FROM contribution_caps
WHERE (cap_type, valid_from) NOT IN (
    VALUES ('pension_health', DATE '2018-01-01'),
           ('unemployment',   DATE '2018-01-01')
);

-- ============================================================
-- 5. Income tax brackets
-- ============================================================
INSERT INTO income_tax_brackets (
    valid_from, valid_to, lower_bound_utm, upper_bound_utm, marginal_rate, rebate_utm
) VALUES
    (DATE '2018-01-01', NULL,    0.0000,   13.5000, 0.000000,  0.0000),
    (DATE '2018-01-01', NULL,   13.5000,   30.0000, 0.040000,  0.5400),
    (DATE '2018-01-01', NULL,   30.0000,   50.0000, 0.080000,  1.7400),
    (DATE '2018-01-01', NULL,   50.0000,   70.0000, 0.135000,  4.4900),
    (DATE '2018-01-01', NULL,   70.0000,   90.0000, 0.230000, 11.1400),
    (DATE '2018-01-01', NULL,   90.0000,  120.0000, 0.304000, 17.8000),
    (DATE '2018-01-01', NULL,  120.0000,  310.0000, 0.350000, 23.3200),
    (DATE '2018-01-01', NULL,  310.0000,      NULL, 0.400000, 38.8200)
ON CONFLICT (valid_from, lower_bound_utm) DO UPDATE
SET
    valid_to        = EXCLUDED.valid_to,
    upper_bound_utm = EXCLUDED.upper_bound_utm,
    marginal_rate   = EXCLUDED.marginal_rate,
    rebate_utm      = EXCLUDED.rebate_utm;

DELETE FROM income_tax_brackets
WHERE (valid_from, lower_bound_utm) NOT IN (
    VALUES (DATE '2018-01-01',   0.0000),
           (DATE '2018-01-01',  13.5000),
           (DATE '2018-01-01',  30.0000),
           (DATE '2018-01-01',  50.0000),
           (DATE '2018-01-01',  70.0000),
           (DATE '2018-01-01',  90.0000),
           (DATE '2018-01-01', 120.0000),
           (DATE '2018-01-01', 310.0000)
);

-- ============================================================
-- 6. Payroll concepts
-- ============================================================
INSERT INTO payroll_concepts (code, name, kind, is_taxable) VALUES
    ('SALARY_BASE',                          'Base Salary',                           'income',   TRUE),
    ('LEGAL_GRATUITY',                       'Legal Gratuity',                        'income',   TRUE),
    ('TELEWORK_REFUND',                      'Telework Refund',                       'income',   FALSE),
    ('HEALTH_INSURANCE_EMPLOYER_CONTRIBUTION','Employer Health Insurance Contribution','income',  TRUE),
    ('VACATION_INCENTIVE',                   'Vacation Incentive',                    'income',   TRUE),
    ('HOLIDAY_BONUS',                        'Holiday Bonus',                         'income',   TRUE),
    ('AVAILABILITY_BONUS',                   'Availability Bonus',                    'income',   TRUE),
    ('LEGAL_GRATUITY_ADJUSTMENT',            'Legal Gratuity Adjustment',             'income',   TRUE),
    ('PRIOR_SALARY_DIFFERENCE',              'Prior Salary Difference',               'income',   TRUE),
    ('PENSION_BASE',                         'Mandatory Pension Contribution',         'discount', FALSE),
    ('PENSION_ADDITIONAL',                   'Additional Pension Contribution',        'discount', FALSE),
    ('HEALTH_BASE',                          'Mandatory Health Contribution',          'discount', FALSE),
    ('HEALTH_ADDITIONAL_UF',                 'Additional Health Charge in UF',         'discount', FALSE),
    ('HEALTH_INSURANCE',                     'Health Insurance',                       'discount', FALSE),
    ('VACATION_BONUS_ADVANCE',               'Vacation Bonus Advance',                 'discount', FALSE),
    ('HOLIDAY_BONUS_ADVANCE',                'Holiday Bonus Advance',                  'discount', FALSE),
    ('SALARY_ADVANCE',                       'Salary Advance',                         'discount', FALSE),
    ('PRIOR_MONTH_LEAVE_ABSENCE_DISCOUNT',   'Prior-Month Leave or Absence Discount',  'discount', FALSE),
    ('UNEMPLOYMENT_INSURANCE',               'Employee Unemployment Insurance',        'discount', FALSE),
    ('INCOME_TAX',                           'Monthly Income Tax Withholding',         'discount', FALSE)
ON CONFLICT (code) DO UPDATE
SET
    name       = EXCLUDED.name,
    kind       = EXCLUDED.kind,
    is_taxable = EXCLUDED.is_taxable;

DELETE FROM payroll_concepts WHERE code NOT IN (
    'SALARY_BASE', 'LEGAL_GRATUITY', 'TELEWORK_REFUND',
    'HEALTH_INSURANCE_EMPLOYER_CONTRIBUTION', 'VACATION_INCENTIVE',
    'HOLIDAY_BONUS', 'AVAILABILITY_BONUS', 'LEGAL_GRATUITY_ADJUSTMENT',
    'PRIOR_SALARY_DIFFERENCE', 'PENSION_BASE', 'PENSION_ADDITIONAL',
    'HEALTH_BASE', 'HEALTH_ADDITIONAL_UF', 'HEALTH_INSURANCE',
    'VACATION_BONUS_ADVANCE', 'HOLIDAY_BONUS_ADVANCE', 'SALARY_ADVANCE',
    'PRIOR_MONTH_LEAVE_ABSENCE_DISCOUNT', 'UNEMPLOYMENT_INSURANCE',
    'INCOME_TAX'
);

COMMIT;
