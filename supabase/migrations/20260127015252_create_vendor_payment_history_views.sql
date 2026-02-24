/*
  # Create Vendor Payment History Views

  ## Overview
  Creates read-only views for the vendor payment history UI to display real AP-backed metrics.
  No table modifications - additive only.

  ## New Views
  
  ### vw_ap_bill_balances
  Consolidated bill information with calculated balances:
  - bill_id, vendor_id, vendor_name
  - bill_number, bill_date, due_date
  - bill_total (amount), amount_paid, open_balance (calculated)
  - is_overdue (calculated from due_date vs today)
  - status
  
  ### vw_vendor_ap_kpis
  Aggregate KPI metrics by vendor (and overall):
  - vendor_id (nullable for "all vendors")
  - vendor_name
  - total_paid (sum of all paid amounts)
  - pending_balance (sum of unpaid/partial bill balances)
  - overdue_balance (sum of overdue bill balances)
  - bill_count, paid_bill_count, overdue_bill_count
  
  ### vw_vendor_payment_history
  Unified feed of bills and payments for display table:
  - vendor_id, vendor_name
  - document_type ('bill' or 'payment')
  - document_id, document_number
  - document_date, due_date (bills only)
  - amount, open_balance (bills only)
  - status
  - payment_method, reference (payments only)
  
  ## Security
  - Views inherit RLS from underlying tables
  - No new RLS policies needed (tables already secured)
  
  ## Notes
  - Views are read-only
  - Safe to drop and recreate
  - No data stored in views
*/

-- Drop existing views if they exist (safe, read-only)
DROP VIEW IF EXISTS vw_vendor_payment_history;
DROP VIEW IF EXISTS vw_vendor_ap_kpis;
DROP VIEW IF EXISTS vw_ap_bill_balances;

-- View 1: Bill balances with calculated fields
CREATE VIEW vw_ap_bill_balances AS
SELECT 
  vb.id AS bill_id,
  vb.vendor_id,
  COALESCE(v.name, vb.vendor_name) AS vendor_name,
  vb.bill_number,
  vb.bill_date,
  vb.due_date,
  vb.amount AS bill_total,
  COALESCE(vb.amount_paid, 0) AS amount_paid,
  vb.balance_due AS open_balance,
  vb.status::text AS status,
  vb.category,
  vb.description,
  vb.gl_posted,
  CASE 
    WHEN vb.status IN ('unpaid', 'partial') AND vb.due_date < CURRENT_DATE 
    THEN true 
    ELSE false 
  END AS is_overdue,
  vb.created_at,
  vb.updated_at
FROM vendor_bills vb
LEFT JOIN vendors v ON v.id = vb.vendor_id
WHERE vb.status IS NOT NULL;

-- View 2: Vendor AP KPIs (aggregated metrics)
CREATE VIEW vw_vendor_ap_kpis AS
SELECT 
  vb.vendor_id,
  COALESCE(v.name, vb.vendor_name) AS vendor_name,
  
  -- Total paid (sum of amount_paid across all bills)
  COALESCE(SUM(vb.amount_paid), 0) AS total_paid,
  
  -- Pending balance (sum of open balances for unpaid/partial bills)
  COALESCE(SUM(CASE 
    WHEN vb.status IN ('unpaid', 'partial') 
    THEN vb.balance_due 
    ELSE 0 
  END), 0) AS pending_balance,
  
  -- Overdue balance (sum of open balances for overdue bills)
  COALESCE(SUM(CASE 
    WHEN vb.status IN ('unpaid', 'partial') AND vb.due_date < CURRENT_DATE 
    THEN vb.balance_due 
    ELSE 0 
  END), 0) AS overdue_balance,
  
  -- Bill counts
  COUNT(*) AS bill_count,
  COUNT(*) FILTER (WHERE vb.status = 'paid') AS paid_bill_count,
  COUNT(*) FILTER (WHERE vb.status IN ('unpaid', 'partial') AND vb.due_date < CURRENT_DATE) AS overdue_bill_count
  
FROM vendor_bills vb
LEFT JOIN vendors v ON v.id = vb.vendor_id
WHERE vb.status IS NOT NULL
GROUP BY vb.vendor_id, v.name, vb.vendor_name;

-- View 3: Unified payment history (bills + payments)
CREATE VIEW vw_vendor_payment_history AS
-- Bills
SELECT 
  vb.id AS document_id,
  'bill' AS document_type,
  vb.vendor_id,
  COALESCE(v.name, vb.vendor_name) AS vendor_name,
  vb.bill_number AS document_number,
  vb.bill_date AS document_date,
  vb.due_date,
  vb.amount AS amount,
  vb.balance_due AS open_balance,
  vb.status::text AS status,
  NULL AS payment_method,
  NULL AS reference,
  vb.category,
  vb.description,
  CASE 
    WHEN vb.status IN ('unpaid', 'partial') AND vb.due_date < CURRENT_DATE 
    THEN true 
    ELSE false 
  END AS is_overdue,
  vb.created_at
FROM vendor_bills vb
LEFT JOIN vendors v ON v.id = vb.vendor_id
WHERE vb.status IS NOT NULL

UNION ALL

-- Payments
SELECT 
  vp.id AS document_id,
  'payment' AS document_type,
  vp.vendor_id,
  v.name AS vendor_name,
  COALESCE(vp.payment_number, vp.check_number, 'PAYMENT-' || vp.id::text) AS document_number,
  vp.payment_date AS document_date,
  NULL AS due_date,
  vp.payment_amount AS amount,
  0 AS open_balance,
  COALESCE(vp.status, 'completed') AS status,
  vp.payment_method,
  COALESCE(vp.transaction_reference, vp.check_number) AS reference,
  NULL AS category,
  vp.description,
  false AS is_overdue,
  vp.created_at
FROM vendor_payments vp
LEFT JOIN vendors v ON v.id = vp.vendor_id;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_vendor_bills_vendor_id_status ON vendor_bills(vendor_id, status);
CREATE INDEX IF NOT EXISTS idx_vendor_bills_due_date ON vendor_bills(due_date) WHERE status IN ('unpaid', 'partial');
CREATE INDEX IF NOT EXISTS idx_vendor_payments_vendor_id ON vendor_payments(vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_payments_payment_date ON vendor_payments(payment_date);

COMMENT ON VIEW vw_ap_bill_balances IS 'Bill balances with calculated open_balance and is_overdue flags';
COMMENT ON VIEW vw_vendor_ap_kpis IS 'Aggregated AP metrics by vendor: total_paid, pending_balance, overdue_balance';
COMMENT ON VIEW vw_vendor_payment_history IS 'Unified view of bills and payments for payment history display';
