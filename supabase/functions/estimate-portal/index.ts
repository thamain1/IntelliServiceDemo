import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Info, Apikey',
};

interface EstimatePortalRequest {
  token: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 200,
      headers: corsHeaders,
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    let token: string;

    if (req.method === 'GET') {
      const url = new URL(req.url);
      token = url.searchParams.get('token') || '';
    } else {
      const requestData: EstimatePortalRequest = await req.json();
      token = requestData.token;
    }

    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Token is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Hash the token
    const encoder = new TextEncoder();
    const data = encoder.encode(token);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const tokenHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    // Find active link by token hash
    const { data: publicLink, error: linkError } = await supabase
      .from('estimate_public_links')
      .select('*')
      .eq('token_hash', tokenHash)
      .is('revoked_at', null)
      .single();

    if (linkError || !publicLink) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired link' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Check expiration
    if (publicLink.expires_at && new Date(publicLink.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: 'This estimate link has expired' }),
        {
          status: 410,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Fetch estimate with line items
    const { data: estimate, error: estimateError } = await supabase
      .from('estimates')
      .select(`
        *,
        customers(id, name, email, phone, address),
        estimate_line_items(*)
      `)
      .eq('id', publicLink.estimate_id)
      .single();

    if (estimateError || !estimate) {
      return new Response(
        JSON.stringify({ error: 'Estimate not found' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Update view tracking
    const newViewCount = (publicLink.view_count || 0) + 1;
    await supabase
      .from('estimate_public_links')
      .update({
        last_viewed_at: new Date().toISOString(),
        view_count: newViewCount,
      })
      .eq('id', publicLink.id);

    // Update estimate viewed_date if first view
    if (!estimate.viewed_date) {
      await supabase
        .from('estimates')
        .update({
          viewed_date: new Date().toISOString(),
          status: estimate.status === 'sent' ? 'viewed' : estimate.status,
        })
        .eq('id', estimate.id);
    }

    // Log event
    await supabase
      .from('estimate_events')
      .insert({
        estimate_id: estimate.id,
        link_id: publicLink.id,
        event_type: 'viewed',
        metadata: {
          view_count: newViewCount,
          user_agent: req.headers.get('user-agent'),
        },
        actor_type: 'customer',
      });

    // Prepare response payload
    const responsePayload = {
      success: true,
      estimate: {
        id: estimate.id,
        estimate_number: estimate.estimate_number,
        customer_name: estimate.customers.name,
        job_title: estimate.job_title,
        job_description: estimate.job_description,
        status: estimate.status,
        estimate_date: estimate.estimate_date,
        expiration_date: estimate.expiration_date,
        subtotal: estimate.subtotal,
        discount_amount: estimate.discount_amount,
        tax_rate: estimate.tax_rate,
        tax_amount: estimate.tax_amount,
        total_amount: estimate.total_amount,
        notes: estimate.notes,
        terms_and_conditions: estimate.terms_and_conditions,
        line_items: estimate.estimate_line_items,
      },
      link: {
        id: publicLink.id,
        decision: publicLink.decision,
        decided_at: publicLink.decided_at,
        decided_name: publicLink.decided_name,
        decision_comment: publicLink.decision_comment,
        expires_at: publicLink.expires_at,
        view_count: newViewCount,
      },
    };

    return new Response(
      JSON.stringify(responsePayload),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        details: error instanceof Error ? error.message : 'Unknown error'
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});
