-- M.A.K Booking — Supabase schema v1.0
-- Run once in a fresh Supabase project using SQL Editor.
-- Includes: profiles/roles, requests, request items, status history,
-- chat, bilingual contracts/signatures, RLS, private storage and Realtime.

begin;

create extension if not exists pgcrypto;

-- ---------- Types ----------
do $$ begin
  create type public.app_role as enum ('client', 'admin');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.service_type as enum ('design', 'web', 'writing');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.request_status as enum (
    'draft',
    'submitted',
    'in_review',
    'awaiting_contract',
    'awaiting_payment',
    'in_progress',
    'completed',
    'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.message_kind as enum ('text', 'image', 'file', 'system');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.contract_status as enum ('draft', 'sent', 'signed', 'void');
exception when duplicate_object then null;
end $$;

-- ---------- Tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null default 'client',
  full_name text not null default '',
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity unique,
  client_id uuid not null references public.profiles(id) on delete cascade,
  service public.service_type not null default 'design',
  status public.request_status not null default 'draft',
  current_step smallint not null default 1 check (current_step between 1 and 6),
  selected_items jsonb not null default '[]'::jsonb,
  selected_mockups jsonb not null default '[]'::jsonb,
  selected_styles jsonb not null default '[]'::jsonb,
  color_palette jsonb not null default '[]'::jsonb,
  brief jsonb not null default '{}'::jsonb,
  notes text,
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  deposit_percentage numeric(5,2) not null default 10 check (deposit_percentage between 0 and 100),
  deposit_amount numeric(12,2) not null default 0 check (deposit_amount >= 0),
  currency text not null default 'MAD' check (currency ~ '^[A-Z]{3}$'),
  verification_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(selected_items) = 'array'),
  check (jsonb_typeof(selected_mockups) = 'array'),
  check (jsonb_typeof(selected_styles) = 'array'),
  check (jsonb_typeof(color_palette) = 'array'),
  check (jsonb_typeof(brief) = 'object')
);

create table if not exists public.request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  item_key text not null,
  title_ar text not null,
  title_en text not null default '',
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null default 1 check (quantity > 0),
  line_total numeric(12,2) generated always as (unit_price * quantity) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (request_id, item_key)
);

create table if not exists public.request_status_history (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.requests(id) on delete cascade,
  status public.request_status not null,
  changed_by uuid references public.profiles(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  kind public.message_kind not null default 'text',
  body text not null default '',
  attachment_path text,
  client_ref uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (kind = 'text' and length(btrim(body)) > 0)
    or (kind <> 'text')
  ),
  check (
    (kind in ('image', 'file') and attachment_path is not null)
    or (kind in ('text', 'system'))
  ),
  unique (sender_id, client_ref)
);

create table if not exists public.contracts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.requests(id) on delete cascade,
  version integer not null default 1 check (version > 0),
  body_ar text not null,
  body_en text not null,
  total numeric(12,2) not null check (total >= 0),
  deposit_amount numeric(12,2) not null check (deposit_amount >= 0),
  currency text not null default 'MAD' check (currency ~ '^[A-Z]{3}$'),
  status public.contract_status not null default 'draft',
  signed_by uuid references public.profiles(id) on delete set null,
  signed_at timestamptz,
  signature_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'signed' and signed_by is not null and signed_at is not null and signature_path is not null)
    or (status <> 'signed' and signed_at is null)
  )
);

-- ---------- Indexes ----------
create index if not exists requests_client_id_idx on public.requests(client_id);
create index if not exists requests_status_idx on public.requests(status);
create index if not exists requests_created_at_idx on public.requests(created_at desc);
create index if not exists request_items_request_id_idx on public.request_items(request_id);
create index if not exists status_history_request_id_idx on public.request_status_history(request_id, created_at desc);
create index if not exists messages_request_id_idx on public.messages(request_id, created_at);
create index if not exists messages_client_ref_idx on public.messages(client_ref) where client_ref is not null;
create index if not exists contracts_request_id_idx on public.contracts(request_id);

-- ---------- Security helper functions ----------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

create or replace function public.can_access_request(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.requests r
    where r.id = p_request_id
      and (r.client_id = (select auth.uid()) or public.is_admin())
  );
$$;

create or replace function public.can_edit_request(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.requests r
    where r.id = p_request_id
      and (
        public.is_admin()
        or (r.client_id = (select auth.uid()) and r.status = 'draft')
      )
  );
$$;

-- ---------- Auth profile creation: first account becomes admin ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  assigned_role public.app_role;
begin
  -- Prevents two simultaneous first sign-ups from both becoming admins.
  perform pg_advisory_xact_lock(741852963);

  if exists (select 1 from public.profiles where role = 'admin') then
    assigned_role := 'client';
  else
    assigned_role := 'admin';
  end if;

  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    assigned_role,
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------- Trigger functions ----------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.guard_profile_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A signed-in client cannot promote themselves or transfer the profile.
  if (select auth.uid()) is not null and not public.is_admin() then
    if new.id is distinct from old.id
      or new.role is distinct from old.role
      or new.created_at is distinct from old.created_at then
      raise exception 'Only an admin can change profile role or ownership';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.guard_request_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null and not public.is_admin() then
      new.client_id := (select auth.uid());
      new.status := 'draft';
      new.submitted_at := null;
    end if;
    new.updated_at := now();
    return new;
  end if;

  if (select auth.uid()) is not null and not public.is_admin() then
    if new.client_id is distinct from old.client_id
      or new.request_number is distinct from old.request_number
      or new.verification_code is distinct from old.verification_code
      or new.created_at is distinct from old.created_at then
      raise exception 'Request ownership and identifiers are immutable';
    end if;

    if old.status <> 'draft' or new.status not in ('draft', 'submitted') then
      raise exception 'A client can only edit a draft or submit it';
    end if;

    if new.status = 'submitted' and old.status = 'draft' then
      if new.total <= 0 then
        raise exception 'Cannot submit a request with a zero total';
      end if;
      new.submitted_at := now();
    elsif new.status = 'draft' then
      new.submitted_at := null;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.log_request_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.request_status_history (request_id, status, changed_by)
    values (new.id, new.status, (select auth.uid()));
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update
before update on public.profiles
for each row execute function public.guard_profile_update();

drop trigger if exists requests_guard_write on public.requests;
create trigger requests_guard_write
before insert or update on public.requests
for each row execute function public.guard_request_write();

drop trigger if exists requests_log_status on public.requests;
create trigger requests_log_status
after insert or update of status on public.requests
for each row execute function public.log_request_status();

drop trigger if exists contracts_touch_updated_at on public.contracts;
create trigger contracts_touch_updated_at
before update on public.contracts
for each row execute function public.touch_updated_at();

-- ---------- Client-safe RPCs ----------
create or replace function public.submit_request(p_request_id uuid)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.requests;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  update public.requests r
  set status = 'submitted', submitted_at = now()
  where r.id = p_request_id
    and r.status = 'draft'
    and r.total > 0
    and (r.client_id = (select auth.uid()) or public.is_admin())
  returning r.* into result;

  if not found then
    raise exception 'Request is missing, not a draft, has a zero total, or is not owned by you';
  end if;

  return result;
end;
$$;

create or replace function public.mark_message_read(p_message_id uuid)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.messages;
begin
  update public.messages m
  set read_at = now()
  where m.id = p_message_id
    and public.can_access_request(m.request_id)
    and m.sender_id is distinct from (select auth.uid())
    and m.read_at is null
  returning m.* into result;

  if not found then
    select m.* into result from public.messages m
    where m.id = p_message_id and public.can_access_request(m.request_id);
  end if;

  if not found then
    raise exception 'Message not found or access denied';
  end if;

  return result;
end;
$$;

create or replace function public.sign_contract(
  p_contract_id uuid,
  p_signature_path text
)
returns public.contracts
language plpgsql
security definer
set search_path = ''
as $$
declare
  contract_row record;
  result public.contracts;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select c.*, r.client_id
  into contract_row
  from public.contracts c
  join public.requests r on r.id = c.request_id
  where c.id = p_contract_id
  for update of c;

  if not found then
    raise exception 'Contract not found';
  end if;

  if contract_row.client_id <> (select auth.uid()) and not public.is_admin() then
    raise exception 'Access denied';
  end if;

  if contract_row.status <> 'sent' then
    raise exception 'Only a sent contract can be signed';
  end if;

  if p_signature_path is null
    or not p_signature_path like contract_row.request_id::text || '/%' then
    raise exception 'Signature must be stored in the request folder';
  end if;

  update public.contracts c
  set status = 'signed',
      signed_by = (select auth.uid()),
      signed_at = now(),
      signature_path = p_signature_path
  where c.id = p_contract_id
  returning c.* into result;

  update public.requests
  set status = 'awaiting_payment'
  where id = contract_row.request_id;

  return result;
end;
$$;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.requests enable row level security;
alter table public.request_items enable row level security;
alter table public.request_status_history enable row level security;
alter table public.messages enable row level security;
alter table public.contracts enable row level security;

-- Profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
for select to authenticated
using (id = (select auth.uid()) or public.is_admin());

drop policy if exists profiles_insert_admin on public.profiles;
create policy profiles_insert_admin on public.profiles
for insert to authenticated
with check (public.is_admin());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
for update to authenticated
using (id = (select auth.uid()) or public.is_admin())
with check (id = (select auth.uid()) or public.is_admin());

drop policy if exists profiles_delete_admin on public.profiles;
create policy profiles_delete_admin on public.profiles
for delete to authenticated
using (public.is_admin());

-- Requests
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests
for select to authenticated
using (client_id = (select auth.uid()) or public.is_admin());

drop policy if exists requests_insert on public.requests;
create policy requests_insert on public.requests
for insert to authenticated
with check (client_id = (select auth.uid()) or public.is_admin());

drop policy if exists requests_update on public.requests;
create policy requests_update on public.requests
for update to authenticated
using (
  public.is_admin()
  or (client_id = (select auth.uid()) and status = 'draft')
)
with check (client_id = (select auth.uid()) or public.is_admin());

drop policy if exists requests_delete on public.requests;
create policy requests_delete on public.requests
for delete to authenticated
using (
  public.is_admin()
  or (client_id = (select auth.uid()) and status = 'draft')
);

-- Request items
drop policy if exists request_items_select on public.request_items;
create policy request_items_select on public.request_items
for select to authenticated
using (public.can_access_request(request_id));

drop policy if exists request_items_insert on public.request_items;
create policy request_items_insert on public.request_items
for insert to authenticated
with check (public.can_edit_request(request_id));

drop policy if exists request_items_update on public.request_items;
create policy request_items_update on public.request_items
for update to authenticated
using (public.can_edit_request(request_id))
with check (public.can_edit_request(request_id));

drop policy if exists request_items_delete on public.request_items;
create policy request_items_delete on public.request_items
for delete to authenticated
using (public.can_edit_request(request_id));

-- Status history is append-only through the database trigger.
drop policy if exists status_history_select on public.request_status_history;
create policy status_history_select on public.request_status_history
for select to authenticated
using (public.can_access_request(request_id));

-- Messages
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
for select to authenticated
using (public.can_access_request(request_id));

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and public.can_access_request(request_id)
  and kind <> 'system'
);

drop policy if exists messages_delete_admin on public.messages;
create policy messages_delete_admin on public.messages
for delete to authenticated
using (public.is_admin());

-- Contracts: admins manage drafts; clients sign through sign_contract().
drop policy if exists contracts_select on public.contracts;
create policy contracts_select on public.contracts
for select to authenticated
using (public.can_access_request(request_id));

drop policy if exists contracts_insert_admin on public.contracts;
create policy contracts_insert_admin on public.contracts
for insert to authenticated
with check (public.is_admin());

drop policy if exists contracts_update_admin on public.contracts;
create policy contracts_update_admin on public.contracts
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists contracts_delete_admin on public.contracts;
create policy contracts_delete_admin on public.contracts
for delete to authenticated
using (public.is_admin());

-- ---------- Private storage ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'request-attachments',
  'request-attachments',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'contract-signatures',
  'contract-signatures',
  false,
  5242880,
  array['image/png', 'image/jpeg']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Object path convention: {request_id}/{filename}
drop policy if exists request_attachments_select on storage.objects;
create policy request_attachments_select on storage.objects
for select to authenticated
using (
  bucket_id = 'request-attachments'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

drop policy if exists request_attachments_insert on storage.objects;
create policy request_attachments_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'request-attachments'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

drop policy if exists request_attachments_update on storage.objects;
create policy request_attachments_update on storage.objects
for update to authenticated
using (
  bucket_id = 'request-attachments'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
)
with check (
  bucket_id = 'request-attachments'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

drop policy if exists request_attachments_delete on storage.objects;
create policy request_attachments_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'request-attachments'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

drop policy if exists contract_signatures_select on storage.objects;
create policy contract_signatures_select on storage.objects
for select to authenticated
using (
  bucket_id = 'contract-signatures'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

drop policy if exists contract_signatures_insert on storage.objects;
create policy contract_signatures_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'contract-signatures'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

drop policy if exists contract_signatures_delete on storage.objects;
create policy contract_signatures_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'contract-signatures'
  and exists (
    select 1 from public.requests r
    where r.id::text = (storage.foldername(name))[1]
      and public.can_access_request(r.id)
  )
);

-- ---------- Grants ----------
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.requests to authenticated;
grant select, insert, update, delete on public.request_items to authenticated;
grant select on public.request_status_history to authenticated;
grant select, insert, delete on public.messages to authenticated;
grant select, insert, update, delete on public.contracts to authenticated;
grant usage, select on all sequences in schema public to authenticated;

revoke all on function public.is_admin() from public, anon;
revoke all on function public.can_access_request(uuid) from public, anon;
revoke all on function public.can_edit_request(uuid) from public, anon;
revoke all on function public.handle_new_user() from public, anon;
revoke all on function public.submit_request(uuid) from public, anon;
revoke all on function public.mark_message_read(uuid) from public, anon;
revoke all on function public.sign_contract(uuid, text) from public, anon;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_access_request(uuid) to authenticated;
grant execute on function public.can_edit_request(uuid) to authenticated;
grant execute on function public.submit_request(uuid) to authenticated;
grant execute on function public.mark_message_read(uuid) to authenticated;
grant execute on function public.sign_contract(uuid, text) to authenticated;

-- ---------- Realtime ----------
alter table public.requests replica identity full;
alter table public.messages replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'requests'
    ) then
      alter publication supabase_realtime add table public.requests;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
    ) then
      alter publication supabase_realtime add table public.messages;
    end if;
  end if;
end $$;

commit;
