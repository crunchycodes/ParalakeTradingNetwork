import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const resendApiKey = Deno.env.get('RESEND_API_KEY');
    const fromEmail = Deno.env.get('NOTIFICATION_FROM_EMAIL') || 'Paralake Trading Network <notifications@example.com>';

    if (!supabaseUrl || !serviceRoleKey || !resendApiKey) {
      throw new Error('Missing notification function secrets.');
    }

    const accessToken = request.headers.get('Authorization')?.replace('Bearer ', '');
    if (!accessToken) {
      return new Response(JSON.stringify({ error: 'Authentication required.' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY') || '', {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const { data: caller, error: callerError } = await userClient.auth.getUser();
    if (callerError || !caller.user) {
      return new Response(JSON.stringify({ error: 'Invalid authentication.' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const payload = await request.json();
    const { sellerUserId, subject, message, link } = payload;

    if (!sellerUserId || !subject || !message) {
      return new Response(JSON.stringify({ error: 'sellerUserId, subject, and message are required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (caller.user.id === sellerUserId) {
      return new Response(JSON.stringify({ error: 'A seller cannot notify themselves.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('email_notifications')
      .eq('id', sellerUserId)
      .single();

    if (profileError) throw profileError;
    if (!profile.email_notifications) {
      return new Response(JSON.stringify({ sent: false, reason: 'disabled' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: userData, error: userError } = await admin.auth.admin.getUserById(sellerUserId);
    if (userError) throw userError;
    const email = userData.user.email;
    if (!email) throw new Error('Seller has no email address.');

    const emailResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [email],
        subject,
        text: `${message}${link ? `\n\nOpen in Paralake Trading Network: ${link}` : ''}`,
      }),
    });

    if (!emailResponse.ok) {
      throw new Error(`Resend request failed: ${await emailResponse.text()}`);
    }

    return new Response(JSON.stringify({ sent: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Notification failed.' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
