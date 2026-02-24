# Estimate Delivery & Customer Review System

## Overview
A complete estimate delivery system with customer portal for viewing, accepting, or rejecting estimates. Features real-time tracking, email/SMS delivery, and full audit trails.

## Database Changes

### New Tables (All Additive)

#### `customer_contacts`
- Customer contact management with email/phone
- Supports multiple contacts per customer
- Flags for primary, billing, and technical contacts
- Opt-in for estimate and invoice delivery

#### `estimate_public_links`
- Secure token-based public links for estimates
- Tracks views, decisions, and expiration
- Token hash storage (plain token never stored)
- Decision capture with name, IP, user agent

#### `estimate_delivery_attempts`
- Audit log of all delivery attempts
- Supports email and SMS channels
- Tracks provider responses and errors
- Delivery status tracking (queued, sent, failed, delivered)

#### `estimate_events`
- Complete audit trail of estimate lifecycle
- Tracks internal, customer, and system events
- JSON metadata for flexible event data
- Actor tracking with IP and user agent

### Security
- All tables have Row Level Security (RLS) enabled
- Public access limited to active, non-expired links
- Token hashing prevents token extraction
- Full audit trail of all actions

## Edge Functions

### 1. `send-estimate` (Authenticated)
Sends estimates to customers via email/SMS.

**Input:**
```typescript
{
  estimate_id: string;
  customer_id?: string;
  contact_id?: string;
  send_email: boolean;
  send_sms: boolean;
  expiration_days?: number; // default 30
}
```

**Process:**
1. Validates user permissions (admin/dispatcher)
2. Generates secure random token (32 bytes)
3. Hashes token with SHA-256 for storage
4. Creates public link record
5. Sends via email and/or SMS (currently simulated)
6. Logs delivery attempts
7. Updates estimate status to 'sent'

**Response:**
```typescript
{
  success: true;
  link_id: string;
  portal_url: string;
  plain_token: string; // Only returned on creation
  delivery_results: Array<{channel, status, to}>;
  expires_at: string | null;
}
```

### 2. `estimate-portal` (Public, No Auth)
Loads estimate details for customer viewing.

**Input:**
```typescript
{
  token: string;
}
```

**Process:**
1. Hashes provided token
2. Finds active link (not revoked, not expired)
3. Loads estimate with line items
4. Updates view tracking (count, last viewed)
5. Logs view event

**Response:**
```typescript
{
  success: true;
  estimate: {
    // Estimate details
    line_items: [];
  };
  link: {
    decision: 'accepted' | 'rejected' | null;
    decided_at: string | null;
    view_count: number;
  };
}
```

### 3. `estimate-decision` (Public, No Auth)
Records customer acceptance or rejection.

**Input:**
```typescript
{
  token: string;
  decision: 'accepted' | 'rejected';
  decided_name: string;
  comment?: string;
}
```

**Process:**
1. Validates token and checks for existing decision
2. Records decision with name, IP, user agent
3. Updates estimate status
4. Logs decision event
5. Prevents duplicate decisions (idempotent)

**Response:**
```typescript
{
  success: true;
  decision: 'accepted' | 'rejected';
  decided_at: string;
  estimate: { id, estimate_number, job_title };
}
```

## Frontend Components

### SendEstimateModal
Modal for sending estimates with:
- Contact selection dropdown
- Email/SMS delivery toggles
- Delivery history display
- Real-time status updates

Used in EstimateDetailModal when clicking "Send Estimate"

### EstimatePortalView
Public-facing customer portal with:
- Professional estimate display
- Line items breakdown
- Pricing summary
- Accept/Decline buttons
- Decision form with name and comment
- Confirmation checkbox
- Decision status display

### EstimateDetailModal Updates
Enhanced with:
- "Send Estimate" button (replaces "Mark as Sent")
- Delivery status card showing:
  - View count and last viewed timestamp
  - Customer decision status
  - Decided by name and timestamp
  - Decision comments

## Routing

### Public Portal Route
`/portal/estimate/:token`

Accessible without authentication. Displays EstimatePortalView.

Example URL:
```
https://your-domain.com/portal/estimate/abc123def456...
```

## User Flow

### 1. Internal User Sends Estimate
1. Open estimate in EstimateDetailModal
2. Click "Send Estimate" button
3. Select contact (or use default customer)
4. Choose email and/or SMS delivery
5. Click "Send Estimate"
6. System generates token and sends notification
7. Delivery history updates with status

### 2. Customer Receives & Views
1. Customer receives email/SMS with portal link
2. Clicks link to open public portal
3. Views estimate details and pricing
4. Portal logs view (updates view count)

### 3. Customer Makes Decision
1. Customer clicks "Accept" or "Decline"
2. Enters their name
3. Optionally adds comment
4. Checks confirmation box
5. Submits decision
6. Decision recorded and estimate updated
7. Cannot change decision after submission

### 4. Internal User Sees Status
1. Open estimate in EstimateDetailModal
2. See "Delivery Status" card with:
   - View tracking
   - Decision status
   - Customer name and timestamp
   - Any comments

## Security Features

1. **Token Security**
   - Cryptographically secure random generation
   - SHA-256 hashing before storage
   - Plain token never stored in database
   - 32-byte minimum length

2. **Access Control**
   - Public links require valid, non-expired token
   - Revocation support for canceling access
   - Expiration dates for time-limited access
   - RLS policies enforce access boundaries

3. **Audit Trail**
   - All actions logged in estimate_events
   - IP address and user agent captured
   - Actor type differentiation (internal/customer/system)
   - Immutable event log

4. **Idempotency**
   - Duplicate decisions prevented
   - Token reuse safe (view tracking)
   - Multiple view logging with count

## Integration Points

### Email Provider (Future)
Currently simulated. To integrate real email:
1. Set environment variable `RESEND_API_KEY`
2. Uncomment Resend API calls in send-estimate function
3. Configure sender domain

### SMS Provider (Future)
Currently simulated. To integrate Twilio:
1. Set environment variables: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`
2. Uncomment Twilio API calls in send-estimate function

## Testing Checklist

- [x] Database migration applies cleanly
- [x] Edge functions deploy successfully
- [x] Send estimate creates link and delivery attempts
- [x] Portal view loads with valid token
- [x] Portal rejects invalid/expired tokens
- [x] Customer can accept estimate
- [x] Customer can reject estimate
- [x] Duplicate decisions prevented
- [x] View tracking increments correctly
- [x] Delivery history displays in modal
- [x] Link status shows in detail modal
- [x] Build completes without errors
- [x] No regressions in existing features

## Future Enhancements

1. **Real Email/SMS Integration**
   - Resend for transactional email
   - Twilio for SMS delivery
   - Delivery status webhooks

2. **Advanced Features**
   - PDF generation for estimates
   - Digital signature capture
   - Multiple approval workflows
   - Reminder notifications
   - Link analytics dashboard

3. **Customer Portal Expansion**
   - Customer login for history access
   - Payment integration
   - Document upload
   - Live chat support

## Environment Variables

Required for full functionality:
- `VITE_SUPABASE_URL` - Supabase project URL
- `VITE_SUPABASE_ANON_KEY` - Supabase anon key
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (auto-configured)
- `RESEND_API_KEY` - (Optional) For real email delivery
- `TWILIO_ACCOUNT_SID` - (Optional) For SMS delivery
- `TWILIO_AUTH_TOKEN` - (Optional) For SMS delivery
- `TWILIO_PHONE_NUMBER` - (Optional) For SMS delivery

## Files Created/Modified

### New Files
- `supabase/migrations/create_estimate_delivery_system.sql`
- `supabase/functions/send-estimate/index.ts`
- `supabase/functions/estimate-portal/index.ts`
- `supabase/functions/estimate-decision/index.ts`
- `src/components/Estimates/SendEstimateModal.tsx`
- `src/components/Estimates/EstimatePortalView.tsx`

### Modified Files
- `src/components/Estimates/EstimateDetailModal.tsx`
  - Added SendEstimateModal integration
  - Added link status display
  - Changed "Mark as Sent" to "Send Estimate"
- `src/App.tsx`
  - Added portal route handling
  - Added EstimatePortalView routing

## Support

For questions or issues:
1. Check database logs for migration errors
2. Check edge function logs in Supabase dashboard
3. Verify RLS policies are active
4. Confirm environment variables are set
5. Test with valid estimate ID and customer contact info
