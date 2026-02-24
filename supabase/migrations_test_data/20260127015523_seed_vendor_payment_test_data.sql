/*
  # Seed Vendor Payment Test Data

  ## Overview
  Creates sample vendor bills and payments for testing the payment history feature.
  Safe to run multiple times (uses INSERT ... ON CONFLICT DO NOTHING).

  ## Test Data
  1. One vendor bill due in future (pending)
  2. One vendor bill past due (overdue)
  3. One paid bill with payment application
  
  ## Notes
  - Uses dev-only test data
  - Safe to delete manually if needed
  - Does NOT affect production data
*/

-- Ensure we have at least one active vendor
DO $$
DECLARE
  v_vendor_id uuid;
  v_admin_id uuid;
BEGIN
  -- Get first admin user for created_by
  SELECT id INTO v_admin_id FROM profiles WHERE role = 'admin' LIMIT 1;
  
  -- Get or create a test vendor
  SELECT id INTO v_vendor_id FROM vendors WHERE name = 'Test Vendor - HVAC Supplies' LIMIT 1;
  
  IF v_vendor_id IS NULL THEN
    INSERT INTO vendors (
      id,
      vendor_code,
      name,
      is_active,
      payment_terms,
      status,
      created_at
    ) VALUES (
      gen_random_uuid(),
      'TEST-VENDOR-001',
      'Test Vendor - HVAC Supplies',
      true,
      'Net 30',
      'active',
      NOW()
    )
    RETURNING id INTO v_vendor_id;
  END IF;

  -- Insert test bill #1: Pending bill (due in 15 days)
  INSERT INTO vendor_bills (
    id,
    bill_number,
    vendor_name,
    vendor_id,
    bill_date,
    due_date,
    amount,
    amount_paid,
    balance_due,
    status,
    category,
    description,
    gl_posted,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    'b1111111-1111-1111-1111-111111111111'::uuid,
    'INV-2026-001',
    'Test Vendor - HVAC Supplies',
    v_vendor_id,
    CURRENT_DATE - INTERVAL '5 days',
    CURRENT_DATE + INTERVAL '15 days',
    2500.00,
    0.00,
    2500.00,
    'unpaid'::ap_status,
    'Parts',
    'HVAC parts and supplies - pending payment',
    false,
    v_admin_id,
    NOW(),
    NOW()
  ) ON CONFLICT (id) DO NOTHING;

  -- Insert test bill #2: Overdue bill (due 10 days ago)
  INSERT INTO vendor_bills (
    id,
    bill_number,
    vendor_name,
    vendor_id,
    bill_date,
    due_date,
    amount,
    amount_paid,
    balance_due,
    status,
    category,
    description,
    gl_posted,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    'b2222222-2222-2222-2222-222222222222'::uuid,
    'INV-2026-002',
    'Test Vendor - HVAC Supplies',
    v_vendor_id,
    CURRENT_DATE - INTERVAL '40 days',
    CURRENT_DATE - INTERVAL '10 days',
    1850.75,
    0.00,
    1850.75,
    'unpaid'::ap_status,
    'Parts',
    'HVAC filters and accessories - OVERDUE',
    false,
    v_admin_id,
    NOW(),
    NOW()
  ) ON CONFLICT (id) DO NOTHING;

  -- Insert test bill #3: Paid bill
  INSERT INTO vendor_bills (
    id,
    bill_number,
    vendor_name,
    vendor_id,
    bill_date,
    due_date,
    amount,
    amount_paid,
    balance_due,
    status,
    category,
    description,
    gl_posted,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    'b3333333-3333-3333-3333-333333333333'::uuid,
    'INV-2026-003',
    'Test Vendor - HVAC Supplies',
    v_vendor_id,
    CURRENT_DATE - INTERVAL '60 days',
    CURRENT_DATE - INTERVAL '30 days',
    3200.50,
    3200.50,
    0.00,
    'paid'::ap_status,
    'Parts',
    'Monthly parts order - paid in full',
    true,
    v_admin_id,
    NOW(),
    NOW()
  ) ON CONFLICT (id) DO NOTHING;

  -- Insert payment for bill #3
  INSERT INTO vendor_payments (
    id,
    vendor_id,
    payment_number,
    payment_date,
    payment_amount,
    payment_method,
    vendor_bill_id,
    check_number,
    transaction_reference,
    description,
    status,
    processed_by,
    processed_at,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    v_vendor_id,
    'PAY-2026-001',
    CURRENT_DATE - INTERVAL '35 days',
    3200.50,
    'check',
    'b3333333-3333-3333-3333-333333333333'::uuid,
    'CHK-5001',
    'CHECK-5001',
    'Payment for INV-2026-003',
    'completed',
    v_admin_id,
    CURRENT_DATE - INTERVAL '35 days',
    v_admin_id,
    NOW(),
    NOW()
  ) ON CONFLICT (id) DO NOTHING;

END $$;
