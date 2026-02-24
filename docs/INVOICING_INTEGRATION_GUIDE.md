# Invoicing Integration & Email Logic: Technical Guide

**Status:** Technical Audit Complete
**Objective:** Transition Invoicing from a "Mailto" fallback to an Enterprise-Grade Automated System.

## Findings Summary
1. **Database:** The `accounting_settings` table is correctly structured and populated by the `CompanySettings` UI.
2. **Missing Integration:** `InvoiceEmailService.ts` currently uses hardcoded "Your Company" strings instead of fetching from `accounting_settings`.
3. **Missing Backend:** The `send-invoice-email` Supabase Edge Function is absent, causing the service to always fall back to the `mailto:` method.

---

## Step 1: Implement Settings Fetching
The `InvoiceEmailService` must be updated to fetch company metadata. 

**Recommended Class Extension:**
```typescript
static async getCompanySettings() {
  const { data } = await supabase
    .from('accounting_settings')
    .select('setting_key, setting_value');

  const settings: any = {};
  data?.forEach(row => {
    settings[row.setting_key] = row.setting_value;
  });

  return {
    companyName: settings.company_name || 'Your Company',
    companyAddress: settings.company_address || '',
    // ... map all other fields like company_phone, email_signature, etc.
  };
}
```

## Step 2: Dynamic PDF Generation
Refactor `generateInvoicePDF` to accept company settings as an argument. Replace the following hardcoded elements:
- `INVOICE` header should be joined by the dynamic `companyName`.
- Footer text should use the `invoice_notes` from settings.
- Company logo should be fetched from `company_logo_url`.

## Step 3: Implement Edge Function
Create `supabase/functions/send-invoice-email/index.ts`. This function should:
1. Receive `to`, `subject`, `body`, and `invoiceId`.
2. Generate the PDF server-side or receive the Blob.
3. Use a provider like **Resend**, **Postmark**, or **SendGrid** to send the email with the PDF as an attachment.
4. Return `{ success: true }` so the frontend can update the invoice status to `sent`.

## Step 4: Refactor InvoicingView
The `handleSend` method in `InvoicingView.tsx` should be fully hooked into the `InvoiceEmailModal`.
- Ensure `onUpdateStatus(invoice.id, 'sent')` is called only after a successful `method: 'function'` return.

---
*Prepared by the Queen of the Codebase for Operation Symbiosis.*
