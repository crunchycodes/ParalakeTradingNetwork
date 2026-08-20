-- Paralake Trading Network marketplace schema
-- Run this in Supabase SQL Editor before enabling invoices or messaging.

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    phone text,
    organization text,
    avatar_url text,
    email_notifications boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.shops (
    slug text primary key,
    display_name text not null,
    owner_user_id uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists public.invoices (
    id uuid primary key default gen_random_uuid(),
    shop_slug text not null references public.shops(slug) on delete restrict,
    buyer_user_id uuid not null references public.profiles(id) on delete restrict,
    seller_user_id uuid not null references public.profiles(id) on delete restrict,
    items jsonb not null default '[]'::jsonb,
    total numeric(12, 2) not null default 0,
    status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'completed', 'cancelled')),
    created_at timestamptz not null default now()
);

create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    shop_slug text not null references public.shops(slug) on delete restrict,
    buyer_user_id uuid not null references public.profiles(id) on delete restrict,
    seller_user_id uuid not null references public.profiles(id) on delete restrict,
    created_at timestamptz not null default now(),
    unique (shop_slug, buyer_user_id, seller_user_id)
);

create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    sender_user_id uuid not null references public.profiles(id) on delete restrict,
    body text not null check (char_length(body) between 1 and 4000),
    created_at timestamptz not null default now()
);

create index if not exists invoices_buyer_idx on public.invoices (buyer_user_id, created_at desc);
create index if not exists invoices_seller_idx on public.invoices (seller_user_id, created_at desc);
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name, avatar_url)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name'),
        new.raw_user_meta_data ->> 'avatar_url'
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.invoices enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert with check (id = auth.uid());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists shops_public_read on public.shops;
create policy shops_public_read on public.shops for select using (true);
drop policy if exists shops_owner_update on public.shops;
create policy shops_owner_update on public.shops for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());

drop policy if exists invoices_participant_read on public.invoices;
create policy invoices_participant_read on public.invoices for select using (buyer_user_id = auth.uid() or seller_user_id = auth.uid());
drop policy if exists invoices_buyer_insert on public.invoices;
create policy invoices_buyer_insert on public.invoices for insert with check (buyer_user_id = auth.uid());
drop policy if exists invoices_participant_update on public.invoices;
create policy invoices_participant_update on public.invoices for update using (buyer_user_id = auth.uid() or seller_user_id = auth.uid()) with check (buyer_user_id = invoices.buyer_user_id and seller_user_id = invoices.seller_user_id);

create or replace function public.is_conversation_member(conversation_uuid uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
    select exists (
        select 1 from public.conversations
        where id = conversation_uuid
          and (buyer_user_id = auth.uid() or seller_user_id = auth.uid())
    );
$$;

drop policy if exists conversations_member_read on public.conversations;
create policy conversations_member_read on public.conversations for select using (buyer_user_id = auth.uid() or seller_user_id = auth.uid());
drop policy if exists conversations_buyer_insert on public.conversations;
create policy conversations_buyer_insert on public.conversations for insert with check (buyer_user_id = auth.uid());

drop policy if exists messages_member_read on public.messages;
create policy messages_member_read on public.messages for select using (public.is_conversation_member(conversation_id));
drop policy if exists messages_member_insert on public.messages;
create policy messages_member_insert on public.messages for insert with check (sender_user_id = auth.uid() and public.is_conversation_member(conversation_id));

-- Add each repository folder manually after assigning its owner:
-- insert into public.shops (slug, display_name, owner_user_id)
-- values ('Samuels-Shop', 'Samuels Shop', 'OWNER-USER-UUID');
