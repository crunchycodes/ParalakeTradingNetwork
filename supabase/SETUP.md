# Supabase Marketplace Setup

## 1. Create the tables and policies

Run `schema.sql` in the Supabase SQL Editor.

Add each repository shop folder manually in the SQL Editor. Replace the owner UUID with the seller's Supabase Auth user ID:

```sql
insert into public.shops (slug, display_name, owner_user_id)
values ('Samuels-Shop', 'Samuels Shop', 'OWNER-USER-UUID');
```

The owner UUID is available in Supabase Dashboard -> Authentication -> Users.

## 2. Configure Resend

Create a Resend API key and configure the sender domain/email in Resend. Then set these Supabase Edge Function secrets:

```text
supabase secrets set RESEND_API_KEY=re_xxxxxxxxx
supabase secrets set NOTIFICATION_FROM_EMAIL="Paralake Trading Network <notifications@your-domain.example>"
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase when the function runs. The service-role key must remain a Supabase secret and must never be committed here.

## 3. Deploy the function

From the repository root after `supabase login` and `supabase link --project-ref fzcmvrsdvgeeuopvxev`:

```text
supabase functions deploy notify-seller
```

The function requires a signed-in user and only sends mail when the seller's `email_notifications` preference is enabled.

## Current scope

The schema supports shop ownership, private invoices, buyer/seller conversations, messages, and seller notification preferences. The shop-page UI still needs the next integration slice to create invoices and conversations against these tables.
