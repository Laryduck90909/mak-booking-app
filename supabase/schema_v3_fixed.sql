-- ============================================================
-- M.A.K BOOKING V3 FINAL (FIXED)
-- Idempotent: safe to re-run on Supabase / Postgres 15+
-- ORDER: 01 Core -> 02 Orders -> 03 Contracts/Payments/Invoices
--        -> 04 Accounting/Scores/Audit -> 05 Storage/Reports/Seeds
-- ============================================================


-- ############################################################
-- PART 01 : CORE / USERS / SETTINGS / HELPERS
-- ############################################################

-- (uuid-ossp not needed: gen_random_uuid() is built in)

-- ------------------------------------------------------------
-- COMPANY SETTINGS
-- ------------------------------------------------------------
create table if not exists public.company_settings (
    id boolean primary key default true,
    company_name text not null default 'M.A.K',
    account_holder text not null default '',
    bank_name text not null default '',
    rib text not null default '',
    tax_id text,
    support_email text not null default '',
    support_phone text not null default '',
    currency_code text not null default 'MAD',
    response_sla_hours integer not null default 8,
    working_hours_per_day integer not null default 8,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint one_settings_row check (id = true)
);

insert into public.company_settings (id)
values (true)
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- PROFILES
-- ------------------------------------------------------------
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text not null unique,
    full_name text not null default '',
    avatar_url text,
    role text not null default 'client'
        check (role in ('client','staff','admin')),
    phone text,
    tax_id text,
    active boolean not null default true,
    last_seen_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_role  on public.profiles(role);
create index if not exists idx_profiles_email on public.profiles(email);

-- ------------------------------------------------------------
-- EMPLOYEE PRIVATE DATA (hourly rate / bank) - admin only
-- (separate from profiles because staff can read all profiles)
-- ------------------------------------------------------------
create table if not exists public.employee_private_data (
    employee_id uuid primary key
        references public.profiles(id) on delete cascade,
    hourly_rate_mad numeric(10,2) not null default 0
        check (hourly_rate_mad >= 0),
    bank_account text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- migrate old databases: move profiles.hourly_rate_mad then drop it
do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'profiles'
          and column_name = 'hourly_rate_mad'
    ) then
        insert into public.employee_private_data (employee_id, hourly_rate_mad)
        select id, hourly_rate_mad
        from public.profiles
        where hourly_rate_mad > 0
        on conflict (employee_id) do nothing;

        alter table public.profiles drop column hourly_rate_mad;
    end if;
end;
$$;

-- ------------------------------------------------------------
-- UPDATED_AT
-- ------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists trg_company_settings_updated_at on public.company_settings;
create trigger trg_company_settings_updated_at
before update on public.company_settings
for each row execute function public.touch_updated_at();

drop trigger if exists trg_employee_private_updated_at on public.employee_private_data;
create trigger trg_employee_private_updated_at
before update on public.employee_private_data
for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- SECURITY HELPERS
-- ------------------------------------------------------------
create or replace function public.user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select role from public.profiles where id = auth.uid() limit 1;
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.profiles
        where id = auth.uid()
          and active
          and role in ('staff','admin')
    );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.profiles
        where id = auth.uid()
          and active
          and role = 'admin'
    );
$$;

-- ------------------------------------------------------------
-- PROTECT SENSITIVE PROFILE COLUMNS
-- (without this, any user could set role = 'admin' on himself)
-- ------------------------------------------------------------
create or replace function public.guard_profile_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    -- auth.uid() is null for service role / SQL editor
    if auth.uid() is not null and not public.is_admin() then
        if new.id              is distinct from old.id
        or new.email           is distinct from old.email
        or new.role            is distinct from old.role
        or new.active          is distinct from old.active
        then
            raise exception 'Not allowed to change protected profile fields';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_profiles_guard on public.profiles;
create trigger trg_profiles_guard
before update on public.profiles
for each row execute function public.guard_profile_update();

-- ------------------------------------------------------------
-- FIRST USER = ADMIN
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    profile_count integer;
begin
    perform pg_advisory_xact_lock(1001);

    select count(*) into profile_count from public.profiles;

    insert into public.profiles (id, email, full_name, role)
    values (
        new.id,
        coalesce(new.email, new.id::text),
        coalesce(new.raw_user_meta_data->>'full_name', ''),
        case when profile_count = 0 then 'admin' else 'client' end
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- SEQUENCES
-- ------------------------------------------------------------
create sequence if not exists public.order_seq    start 1;
create sequence if not exists public.contract_seq start 1;
create sequence if not exists public.invoice_seq  start 1;

-- ------------------------------------------------------------
-- UNIQUE VERIFICATION CODE
-- security definer: clients cannot see other clients' orders
-- under RLS, so the uniqueness check must bypass RLS.
-- ------------------------------------------------------------
create or replace function public.generate_unique_verification_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_code text;
begin
    loop
        v_code := lpad((floor(random() * 90000) + 10000)::int::text, 5, '0');
        exit when not exists (
            select 1 from public.orders where verification_code = v_code
        );
    end loop;
    return v_code;
end;
$$;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table public.profiles         enable row level security;
alter table public.company_settings enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
on public.profiles for select
using (auth.uid() = id or public.is_staff());

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update
on public.profiles for update
using (public.is_admin())
with check (public.is_admin());

drop policy if exists company_settings_read on public.company_settings;
create policy company_settings_read
on public.company_settings for select
to authenticated
using (true);

drop policy if exists company_settings_admin on public.company_settings;
create policy company_settings_admin
on public.company_settings for all
using (public.is_admin())
with check (public.is_admin());

alter table public.employee_private_data enable row level security;

drop policy if exists employee_private_admin on public.employee_private_data;
create policy employee_private_admin
on public.employee_private_data for all
using (public.is_admin())
with check (public.is_admin());

-- an employee may read his own row only
drop policy if exists employee_private_self_read on public.employee_private_data;
create policy employee_private_self_read
on public.employee_private_data for select
using (employee_id = auth.uid());


-- ############################################################
-- PART 02 : ORDERS / ASSIGNMENTS / WORKLOGS
--           QUOTES / NOTIFICATIONS / MESSAGES
-- ############################################################

-- ------------------------------------------------------------
-- ORDERS
-- ------------------------------------------------------------
create table if not exists public.orders (
    id text primary key default (
        'MAK-' || to_char(now(),'YYYY') || '-' ||
        lpad(nextval('public.order_seq')::text, 4, '0')
    ),
    client_id uuid not null
        references public.profiles(id) on delete restrict,
    section text not null
        check (section in ('design','web','writing')),
    title text not null default '',
    status text not null default 'new'
        check (status in (
            'new','quoted','accepted','rejected','expired',
            'contract_pending','in_progress','preview_sent',
            'paid','delivered','completed','cancelled'
        )),
    payload jsonb not null default '{}'::jsonb,
    total_mad integer not null default 0,
    deposit_mad integer not null default 0,
    verification_code text not null
        default public.generate_unique_verification_code(),
    execution_started_at timestamptz,
    cancelled_at timestamptz,
    completed_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint orders_amounts_valid check (
        total_mad >= 0 and deposit_mad >= 0 and deposit_mad <= total_mad
    )
);

create unique index if not exists idx_orders_verification on public.orders(verification_code);
create index if not exists idx_orders_client  on public.orders(client_id);
create index if not exists idx_orders_status  on public.orders(status);
create index if not exists idx_orders_section on public.orders(section);
create index if not exists idx_orders_deleted on public.orders(deleted_at);

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at
before update on public.orders
for each row execute function public.touch_updated_at();

-- verification_code is always server-generated for API users:
-- a client cannot choose it on insert, nobody can change it later.
-- (service role / SQL editor, where auth.uid() is null, is unrestricted)
create or replace function public.orders_enforce_verification_code()
returns trigger
language plpgsql
as $$
begin
    if auth.uid() is not null then
        if tg_op = 'INSERT' then
            new.verification_code := public.generate_unique_verification_code();
        elsif new.verification_code is distinct from old.verification_code then
            raise exception 'Verification code cannot be changed';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_orders_verification_code on public.orders;
create trigger trg_orders_verification_code
before insert or update on public.orders
for each row execute function public.orders_enforce_verification_code();

-- cancelled_at / completed_at set automatically
create or replace function public.orders_status_timestamps()
returns trigger
language plpgsql
as $$
begin
    if new.status is distinct from old.status then
        if new.status = 'cancelled' then
            new.cancelled_at := coalesce(new.cancelled_at, now());
        elsif new.status = 'completed' then
            new.completed_at := coalesce(new.completed_at, now());
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_orders_status_timestamps on public.orders;
create trigger trg_orders_status_timestamps
before update on public.orders
for each row execute function public.orders_status_timestamps();

-- ------------------------------------------------------------
-- ORDER ASSIGNMENTS
-- ------------------------------------------------------------
create table if not exists public.order_assignments (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders(id) on delete cascade,
    employee_id uuid not null references public.profiles(id) on delete cascade,
    assigned_by uuid references public.profiles(id),
    role text not null check (role in (
        'manager','designer','developer','writer','translator','reviewer'
    )),
    assigned_at timestamptz not null default now(),
    unique (order_id, employee_id)
);

create index if not exists idx_assignment_order    on public.order_assignments(order_id);
create index if not exists idx_assignment_employee on public.order_assignments(employee_id);

-- ------------------------------------------------------------
-- EMPLOYEE WORKLOGS
-- ------------------------------------------------------------
create table if not exists public.employee_worklogs (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders(id) on delete cascade,
    employee_id uuid not null references public.profiles(id) on delete cascade,
    work_date date not null default current_date,
    hours numeric(6,2) not null check (hours > 0 and hours <= 24),
    description text not null default '',
    approved_by uuid references public.profiles(id),
    approved_at timestamptz,
    created_at timestamptz not null default now()
);

-- for databases created from the old version
alter table public.employee_worklogs
    add column if not exists approved_by uuid references public.profiles(id);
alter table public.employee_worklogs
    add column if not exists approved_at timestamptz;

create index if not exists idx_worklogs_employee on public.employee_worklogs(employee_id);
create index if not exists idx_worklogs_order    on public.employee_worklogs(order_id);

-- ------------------------------------------------------------
-- QUOTES
-- ------------------------------------------------------------
create table if not exists public.quotes (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders(id) on delete cascade,
    base_total_mad integer not null check (base_total_mad >= 0),
    variable_delta_mad integer not null default 0,
    final_total_mad integer generated always as (
        base_total_mad + variable_delta_mad
    ) stored,
    note text not null default '',
    proposed_by uuid references public.profiles(id),
    approved_by uuid references public.profiles(id),
    valid_until date,
    status text not null default 'pending_approval'
        check (status in (
            'pending_approval','approved','rejected','sent','accepted','expired'
        )),
    created_at timestamptz not null default now()
);

create index if not exists idx_quotes_order on public.quotes(order_id);

-- ------------------------------------------------------------
-- NOTIFICATIONS
-- ------------------------------------------------------------
create table if not exists public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    type text not null default 'system'
        check (type in ('message','quote','contract','payment','system')),
    title text not null,
    body text not null default '',
    link text not null default '',
    read_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user
on public.notifications(user_id, created_at desc);

create index if not exists idx_notifications_read
on public.notifications(user_id, read_at);

-- ------------------------------------------------------------
-- MESSAGES
-- ------------------------------------------------------------
create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders(id) on delete cascade,
    sender_id uuid not null references public.profiles(id) on delete restrict,
    body text not null,
    attachment_path text,
    created_at timestamptz not null default now()
);

create index if not exists idx_messages_order
on public.messages(order_id, created_at);

-- ------------------------------------------------------------
-- NOTIFICATION HELPER (internal only: see REVOKE at the end)
-- ------------------------------------------------------------
create or replace function public.create_notification(
    p_user uuid,
    p_type text,
    p_title text,
    p_body text,
    p_link text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.notifications (user_id, type, title, body, link)
    values (p_user, p_type, p_title, p_body, p_link);
end;
$$;

-- nobody can call it directly through the API (prevents spam);
-- triggers/security-definer functions still can.
revoke all on function public.create_notification(uuid,text,text,text,text)
from public, anon, authenticated;

-- ------------------------------------------------------------
-- ORDER STATUS NOTIFICATION
-- ------------------------------------------------------------
create or replace function public.notify_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status is distinct from old.status then
        perform public.create_notification(
            new.client_id,
            'system',
            'تحديث حالة الطلب',
            'تم تحديث حالة الطلب ' || new.id,
            '/orders/' || new.id
        );
    end if;
    return new;
end;
$$;

drop trigger if exists trg_order_status_notification on public.orders;
create trigger trg_order_status_notification
after update on public.orders
for each row execute function public.notify_order_status();

-- ------------------------------------------------------------
-- NEW MESSAGE NOTIFICATION
-- ------------------------------------------------------------
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_client   uuid;
    v_rec      record;
    v_notified boolean := false;
begin
    select client_id into v_client
    from public.orders where id = new.order_id;

    if new.sender_id is distinct from v_client then
        perform public.create_notification(
            v_client, 'message', 'رسالة جديدة',
            'لديك رسالة جديدة على الطلب ' || new.order_id,
            '/orders/' || new.order_id
        );
    else
        for v_rec in
            select employee_id as uid
            from public.order_assignments
            where order_id = new.order_id
        loop
            perform public.create_notification(
                v_rec.uid, 'message', 'رسالة جديدة من العميل',
                'رسالة جديدة على الطلب ' || new.order_id,
                '/orders/' || new.order_id
            );
            v_notified := true;
        end loop;

        if not v_notified then
            for v_rec in
                select id as uid from public.profiles
                where role = 'admin' and active
            loop
                perform public.create_notification(
                    v_rec.uid, 'message', 'رسالة جديدة من العميل',
                    'رسالة جديدة على الطلب ' || new.order_id,
                    '/orders/' || new.order_id
                );
            end loop;
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_message_notification on public.messages;
create trigger trg_message_notification
after insert on public.messages
for each row execute function public.notify_new_message();

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table public.orders            enable row level security;
alter table public.order_assignments enable row level security;
alter table public.employee_worklogs enable row level security;
alter table public.quotes            enable row level security;
alter table public.notifications     enable row level security;
alter table public.messages          enable row level security;

-- ORDERS
drop policy if exists orders_insert_client on public.orders;
create policy orders_insert_client
on public.orders for insert
with check (
    auth.uid() = client_id
    and status = 'new'
    and total_mad = 0
    and deposit_mad = 0
    and deleted_at is null
    and execution_started_at is null
    and completed_at is null
    and cancelled_at is null
);

drop policy if exists orders_select on public.orders;
create policy orders_select
on public.orders for select
using (
    (auth.uid() = client_id and deleted_at is null)
    or public.is_staff()
);

drop policy if exists orders_update_staff on public.orders;
create policy orders_update_staff
on public.orders for update
using (public.is_staff())
with check (public.is_staff());

-- ASSIGNMENTS
drop policy if exists assignments_staff_select on public.order_assignments;
create policy assignments_staff_select
on public.order_assignments for select
using (public.is_staff());

drop policy if exists assignments_admin_all on public.order_assignments;
create policy assignments_admin_all
on public.order_assignments for all
using (public.is_admin())
with check (public.is_admin());

-- WORKLOGS
drop policy if exists worklogs_staff_read on public.employee_worklogs;
create policy worklogs_staff_read
on public.employee_worklogs for select
using (public.is_staff());

drop policy if exists worklogs_staff_write on public.employee_worklogs;
create policy worklogs_staff_write
on public.employee_worklogs for insert
with check (
    public.is_staff()
    and (employee_id = auth.uid() or public.is_admin())
    and approved_at is null
    and approved_by is null
);

drop policy if exists worklogs_admin_update on public.employee_worklogs;
create policy worklogs_admin_update
on public.employee_worklogs for update
using (public.is_admin())
with check (public.is_admin());

-- QUOTES
drop policy if exists quotes_staff_all on public.quotes;
create policy quotes_staff_all
on public.quotes for all
using (public.is_staff())
with check (public.is_staff());

drop policy if exists quotes_client_read on public.quotes;
create policy quotes_client_read
on public.quotes for select
using (
    quotes.status in ('sent','accepted','expired')
    and exists (
        select 1 from public.orders o
        where o.id = quotes.order_id
          and o.client_id = auth.uid()
          and o.deleted_at is null
    )
);

-- NOTIFICATIONS (no client insert: created only by the system)
drop policy if exists notifications_own on public.notifications;
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
on public.notifications for select
using (auth.uid() = user_id);

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
on public.notifications for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own
on public.notifications for delete
using (auth.uid() = user_id);

-- MESSAGES
drop policy if exists messages_select on public.messages;
create policy messages_select
on public.messages for select
using (
    public.is_staff()
    or auth.uid() = sender_id
    or exists (
        select 1 from public.orders o
        where o.id = messages.order_id
          and o.client_id = auth.uid()
          and o.deleted_at is null
    )
);

drop policy if exists messages_insert on public.messages;
create policy messages_insert
on public.messages for insert
with check (
    auth.uid() = sender_id
    and (
        public.is_staff()
        or exists (
            select 1 from public.orders o
            where o.id = messages.order_id
              and o.client_id = auth.uid()
              and o.deleted_at is null
        )
    )
);


-- ------------------------------------------------------------
-- QUOTE SENT -> ORDER BECOMES 'quoted' + CLIENT NOTIFIED
-- ------------------------------------------------------------
create or replace function public.quote_sent_hook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_prev   text;
    v_client uuid;
begin
    if tg_op = 'UPDATE' then
        v_prev := old.status;
    end if;

    if new.status = 'sent' and v_prev is distinct from 'sent' then
        select client_id into v_client
        from public.orders where id = new.order_id;

        update public.orders
        set status = 'quoted'
        where id = new.order_id
          and status = 'new';

        perform public.create_notification(
            v_client,
            'quote',
            'عرض سعر جديد',
            'تم إرسال عرض سعر لطلبك ' || new.order_id,
            '/orders/' || new.order_id
        );
    end if;

    return new;
end;
$$;

drop trigger if exists trg_quote_sent on public.quotes;
create trigger trg_quote_sent
after insert or update on public.quotes
for each row execute function public.quote_sent_hook();

-- ------------------------------------------------------------
-- CLIENT ACCEPTS A QUOTE
-- returns true when accepted, false when the quote had expired
-- ------------------------------------------------------------
create or replace function public.accept_quote(
    p_quote_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_quote public.quotes%rowtype;
    v_order public.orders%rowtype;
    v_admin record;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select * into v_quote
    from public.quotes
    where id = p_quote_id
    for update;

    if not found then
        raise exception 'Quote not found';
    end if;

    select * into v_order
    from public.orders
    where id = v_quote.order_id
      and client_id = auth.uid()
      and deleted_at is null
    for update;

    if not found then
        raise exception 'Not allowed';
    end if;

    if v_quote.status <> 'sent' or v_order.status <> 'quoted' then
        raise exception 'Quote is not open for a response';
    end if;

    if v_quote.valid_until is not null
       and v_quote.valid_until < current_date then
        update public.quotes set status = 'expired' where id = p_quote_id;
        update public.orders set status = 'expired' where id = v_order.id;
        return false;
    end if;

    update public.quotes
    set status = 'accepted'
    where id = p_quote_id;

    -- the accepted quote fixes the order price
    update public.orders
    set status = 'accepted',
        total_mad = v_quote.final_total_mad,
        deposit_mad = least(v_order.deposit_mad, v_quote.final_total_mad)
    where id = v_order.id;

    for v_admin in
        select id from public.profiles where role = 'admin' and active
    loop
        perform public.create_notification(
            v_admin.id,
            'quote',
            'تم قبول عرض السعر',
            'قبل العميل عرض السعر للطلب ' || v_order.id,
            '/orders/' || v_order.id
        );
    end loop;

    return true;
end;
$$;

-- ------------------------------------------------------------
-- CLIENT REJECTS A QUOTE
-- ------------------------------------------------------------
create or replace function public.reject_quote(
    p_quote_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_quote public.quotes%rowtype;
    v_order public.orders%rowtype;
    v_admin record;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select * into v_quote
    from public.quotes
    where id = p_quote_id
    for update;

    if not found then
        raise exception 'Quote not found';
    end if;

    select * into v_order
    from public.orders
    where id = v_quote.order_id
      and client_id = auth.uid()
      and deleted_at is null
    for update;

    if not found then
        raise exception 'Not allowed';
    end if;

    if v_quote.status <> 'sent' or v_order.status <> 'quoted' then
        raise exception 'Quote is not open for a response';
    end if;

    update public.quotes
    set status = 'rejected'
    where id = p_quote_id;

    update public.orders
    set status = 'rejected'
    where id = v_order.id;

    for v_admin in
        select id from public.profiles where role = 'admin' and active
    loop
        perform public.create_notification(
            v_admin.id,
            'quote',
            'تم رفض عرض السعر',
            'رفض العميل عرض السعر للطلب ' || v_order.id,
            '/orders/' || v_order.id
        );
    end loop;

    return true;
end;
$$;

revoke all on function public.accept_quote(uuid) from public, anon, authenticated;
revoke all on function public.reject_quote(uuid) from public, anon, authenticated;
grant execute on function public.accept_quote(uuid) to authenticated;
grant execute on function public.reject_quote(uuid) to authenticated;

-- ############################################################
-- PART 03 : CONTRACTS / PAYMENTS / INVOICES
-- ############################################################

-- ------------------------------------------------------------
-- CONTRACT TEMPLATES
-- ------------------------------------------------------------
create table if not exists public.contract_templates (
    id uuid primary key default gen_random_uuid(),
    section text not null
        check (section in ('design','web','writing','general')),
    title text not null,
    body_ar text not null,
    body_en text not null,
    updated_at timestamptz not null default now(),
    unique (section, title)
);

alter table public.contract_templates
    add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_contract_templates_section
on public.contract_templates(section);

drop trigger if exists trg_contract_templates_updated_at on public.contract_templates;
create trigger trg_contract_templates_updated_at
before update on public.contract_templates
for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- CONTRACTS
-- Flow: draft -> awaiting_client -> awaiting_admin -> signed
-- (client signs first, then admin)
-- ------------------------------------------------------------
create table if not exists public.contracts (
    id text primary key default (
        'CON-' || to_char(now(),'YYYY') || '-' ||
        lpad(nextval('public.contract_seq')::text, 4, '0')
    ),
    order_id text not null references public.orders(id) on delete cascade,
    template_id uuid references public.contract_templates(id),
    rendered_ar text not null default '',
    rendered_en text not null default '',
    pdf_path text,
    client_signature text,
    admin_signature text,
    status text not null default 'draft'
        check (status in (
            'draft','awaiting_client','awaiting_admin','signed','void'
        )),
    signed_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),

    -- final contract must carry the admin signature
    constraint contract_requires_admin_signature
        check (status <> 'signed' or admin_signature is not null),

    -- admin step requires the client to have signed already
    constraint contract_requires_client_signature
        check (
            status not in ('awaiting_admin','signed')
            or client_signature is not null
        ),

    constraint client_signs_first
        check (admin_signature is null or client_signature is not null)
);

create index if not exists idx_contract_order   on public.contracts(order_id);
create index if not exists idx_contract_status  on public.contracts(status);
create index if not exists idx_contract_deleted on public.contracts(deleted_at);

-- ------------------------------------------------------------
-- CONTRACT GUARD
-- signatures / signed status can only change through
-- sign_contract() and admin_sign_contract().
-- ------------------------------------------------------------
create or replace function public.guard_contract_changes()
returns trigger
language plpgsql
as $$
declare
    v_flag boolean := coalesce(current_setting('app.contract_sign', true), '') = 'on';
begin
    -- service role / SQL editor: no restriction
    if auth.uid() is null then
        return new;
    end if;

    if tg_op = 'INSERT' then
        if not v_flag and (
            new.client_signature is not null
            or new.admin_signature is not null
            or new.signed_at is not null
            or new.status in ('awaiting_admin','signed')
        ) then
            raise exception 'Contracts must be signed through the signing functions';
        end if;
        return new;
    end if;

    -- UPDATE
    if old.status = 'signed' and (
        new.rendered_ar      is distinct from old.rendered_ar
        or new.rendered_en   is distinct from old.rendered_en
        or new.client_signature is distinct from old.client_signature
        or new.admin_signature  is distinct from old.admin_signature
        or new.status        is distinct from old.status
        or new.signed_at     is distinct from old.signed_at
        or new.order_id      is distinct from old.order_id
    ) then
        raise exception 'Signed contracts are immutable';
    end if;

    if not v_flag and (
        new.client_signature is distinct from old.client_signature
        or new.admin_signature is distinct from old.admin_signature
        or new.signed_at       is distinct from old.signed_at
        or (
            new.status is distinct from old.status
            and new.status in ('awaiting_admin','signed')
        )
    ) then
        raise exception 'Contracts must be signed through the signing functions';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_contract_guard on public.contracts;
create trigger trg_contract_guard
before insert or update on public.contracts
for each row execute function public.guard_contract_changes();

-- ------------------------------------------------------------
-- CLIENT SIGNS (first)
-- ------------------------------------------------------------
create or replace function public.sign_contract(
    p_contract_id text,
    p_signature text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_contract public.contracts%rowtype;
    v_admin    record;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if coalesce(btrim(p_signature), '') = '' then
        raise exception 'Signature is required';
    end if;

    select * into v_contract
    from public.contracts
    where id = p_contract_id
      and deleted_at is null
    for update;

    if not found then
        raise exception 'Contract not found';
    end if;

    if not exists (
        select 1 from public.orders o
        where o.id = v_contract.order_id
          and o.client_id = auth.uid()
    ) then
        raise exception 'Not allowed';
    end if;

    if v_contract.status <> 'awaiting_client' then
        raise exception 'Contract is not awaiting the client signature';
    end if;

    if not exists (
        select 1 from public.orders o
        where o.id = v_contract.order_id
          and o.status in ('accepted','contract_pending')
          and o.deleted_at is null
    ) then
        raise exception 'Order is not in a state that allows contract signing';
    end if;

    perform set_config('app.contract_sign', 'on', true);

    update public.contracts
    set client_signature = p_signature,
        status = 'awaiting_admin'
    where id = p_contract_id;

    perform set_config('app.contract_sign', 'off', true);

    for v_admin in
        select id from public.profiles
        where role = 'admin' and active
    loop
        perform public.create_notification(
            v_admin.id,
            'contract',
            'عقد بانتظار توقيع المدير',
            'يوجد عقد جديد يحتاج الاعتماد',
            '/contracts/' || p_contract_id
        );
    end loop;

    return true;
end;
$$;

-- ------------------------------------------------------------
-- ADMIN SIGNS (second, final)
-- ------------------------------------------------------------
create or replace function public.admin_sign_contract(
    p_contract_id text,
    p_signature text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_contract public.contracts%rowtype;
begin
    if not public.is_admin() then
        raise exception 'Not allowed';
    end if;

    if coalesce(btrim(p_signature), '') = '' then
        raise exception 'Signature is required';
    end if;

    select * into v_contract
    from public.contracts
    where id = p_contract_id
      and deleted_at is null
    for update;

    if not found then
        raise exception 'Contract not found';
    end if;

    if v_contract.status <> 'awaiting_admin'
       or v_contract.client_signature is null then
        raise exception 'Contract is not awaiting the admin signature';
    end if;

    if not exists (
        select 1 from public.orders o
        where o.id = v_contract.order_id
          and o.status in ('accepted','contract_pending')
          and o.deleted_at is null
    ) then
        raise exception 'Order is not in a state that allows contract signing';
    end if;

    perform set_config('app.contract_sign', 'on', true);

    update public.contracts
    set admin_signature = p_signature,
        status = 'signed',
        signed_at = now()
    where id = p_contract_id;

    perform set_config('app.contract_sign', 'off', true);

    return true;
end;
$$;

revoke all on function public.sign_contract(text,text)       from public, anon, authenticated;
revoke all on function public.admin_sign_contract(text,text) from public, anon, authenticated;
grant execute on function public.sign_contract(text,text)       to authenticated;
grant execute on function public.admin_sign_contract(text,text) to authenticated;

-- ------------------------------------------------------------
-- CONTRACT SIGNED -> START ORDER EXECUTION
-- (moved here: needs public.contracts to exist)
-- ------------------------------------------------------------
create or replace function public.contract_signed_hook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'signed' and old.status is distinct from 'signed' then
        update public.orders
        set status = 'in_progress',
            execution_started_at = coalesce(execution_started_at, now())
        where id = new.order_id
          and status in ('accepted','contract_pending');
    end if;
    return new;
end;
$$;

drop trigger if exists trg_contract_signed on public.contracts;
create trigger trg_contract_signed
after update on public.contracts
for each row execute function public.contract_signed_hook();

create or replace function public.notify_contract_signed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_client uuid;
begin
    if new.status = 'signed' and old.status is distinct from 'signed' then
        select client_id into v_client
        from public.orders
        where id = new.order_id;

        perform public.create_notification(
            v_client,
            'contract',
            'تم توقيع العقد',
            'تم اعتماد العقد الخاص بطلبك',
            '/contracts/' || new.id
        );
    end if;
    return new;
end;
$$;

drop trigger if exists trg_contract_notification on public.contracts;
create trigger trg_contract_notification
after update on public.contracts
for each row execute function public.notify_contract_signed();

-- ------------------------------------------------------------
-- PAYMENTS
-- ------------------------------------------------------------
create table if not exists public.payments (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders(id) on delete cascade,
    kind text not null
        check (kind in ('deposit','full','fine','modification')),
    amount_mad integer not null check (amount_mad > 0),
    method text not null default 'bank'
        check (method in ('bank','cash')),
    receipt_path text,
    confirmed_by uuid references public.profiles(id),
    confirmed_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists idx_payments_order     on public.payments(order_id);
create index if not exists idx_payments_confirmed on public.payments(confirmed_at);
create index if not exists idx_payment_deleted    on public.payments(deleted_at);

-- for databases created from the old version
alter table public.payments
    add column if not exists method text not null default 'bank'
    check (method in ('bank','cash'));

-- confirmed payments are locked; confirmation time is always server time
-- (replaces the invalid "confirmed_at <= now()" CHECK)
create or replace function public.lock_confirmed_payment()
returns trigger
language plpgsql
as $$
begin
    if old.confirmed_at is not null then
        raise exception 'Confirmed payments cannot be modified';
    end if;

    if new.confirmed_at is not null then
        new.confirmed_at := now();
        new.confirmed_by := coalesce(auth.uid(), new.confirmed_by);
    end if;

    return new;
end;
$$;

drop trigger if exists trg_lock_payment on public.payments;
create trigger trg_lock_payment
before update on public.payments
for each row execute function public.lock_confirmed_payment();

-- ------------------------------------------------------------
-- INVOICES
-- ------------------------------------------------------------
create table if not exists public.invoices (
    id text primary key default (
        'INV-' || to_char(now(),'YYYY') || '-' ||
        lpad(nextval('public.invoice_seq')::text, 4, '0')
    ),
    order_id text references public.orders(id) on delete set null,
    client_name text not null,
    lines jsonb not null default '[]'::jsonb,
    total_mad integer not null default 0,
    pdf_path text,
    deleted_at timestamptz,
    status text not null default 'issued'
        check (status in ('issued','paid','cancelled')),
    issued_at timestamptz not null default now(),
    constraint invoice_total_positive check (total_mad >= 0)
);

create index if not exists idx_invoice_order   on public.invoices(order_id);
create index if not exists idx_invoice_deleted on public.invoices(deleted_at);

-- ------------------------------------------------------------
-- CREATE INVOICE AFTER PAYMENT CONFIRMATION
-- ------------------------------------------------------------
create or replace function public.create_invoice_after_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order public.orders%rowtype;
begin
    if new.confirmed_at is not null and old.confirmed_at is null then

        select * into v_order
        from public.orders
        where id = new.order_id;

        if not exists (
            select 1 from public.invoices
            where order_id = new.order_id
              and deleted_at is null
        ) then
            insert into public.invoices (order_id, client_name, total_mad, lines)
            values (
                v_order.id,
                coalesce(
                    nullif((select full_name from public.profiles where id = v_order.client_id), ''),
                    (select email from public.profiles where id = v_order.client_id),
                    ''
                ),
                v_order.total_mad,
                jsonb_build_array(
                    jsonb_build_object(
                        'label',  v_order.title,
                        'amount', v_order.total_mad
                    )
                )
            );
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_invoice_creation on public.payments;
create trigger trg_invoice_creation
after update on public.payments
for each row execute function public.create_invoice_after_payment();

-- ------------------------------------------------------------
-- PAYMENT NOTIFICATIONS
-- ------------------------------------------------------------
create or replace function public.notify_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_client uuid;
begin
    if new.confirmed_at is not null and old.confirmed_at is null then
        select client_id into v_client
        from public.orders
        where id = new.order_id;

        perform public.create_notification(
            v_client,
            'payment',
            'تم تأكيد الدفع',
            'تم تأكيد الدفع للطلب ' || new.order_id,
            '/orders/' || new.order_id
        );
    end if;
    return new;
end;
$$;

drop trigger if exists trg_payment_notify on public.payments;
create trigger trg_payment_notify
after update on public.payments
for each row execute function public.notify_payment();

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table public.contract_templates enable row level security;
alter table public.contracts          enable row level security;
alter table public.payments           enable row level security;
alter table public.invoices           enable row level security;

-- CONTRACT TEMPLATES
drop policy if exists contract_templates_public_read on public.contract_templates;
drop policy if exists contract_templates_read on public.contract_templates;
create policy contract_templates_read
on public.contract_templates for select
to authenticated
using (true);

drop policy if exists contract_templates_admin_all on public.contract_templates;
create policy contract_templates_admin_all
on public.contract_templates for all
using (public.is_admin())
with check (public.is_admin());

-- CONTRACTS
drop policy if exists contracts_staff_read on public.contracts;
create policy contracts_staff_read
on public.contracts for select
using (
    public.is_staff()
    or (
        contracts.deleted_at is null
        and exists (
            select 1 from public.orders o
            where o.id = contracts.order_id
              and o.client_id = auth.uid()
        )
    )
);

drop policy if exists contracts_staff_write on public.contracts;
drop policy if exists contracts_staff_insert on public.contracts;
create policy contracts_staff_insert
on public.contracts for insert
with check (public.is_staff());

drop policy if exists contracts_staff_update on public.contracts;
create policy contracts_staff_update
on public.contracts for update
using (public.is_staff())
with check (public.is_staff());

drop policy if exists contracts_admin_delete on public.contracts;
create policy contracts_admin_delete
on public.contracts for delete
using (public.is_admin());

-- PAYMENTS
drop policy if exists payments_insert_client on public.payments;
create policy payments_insert_client
on public.payments for insert
with check (
    payments.kind in ('deposit','full')
    and payments.confirmed_at is null
    and payments.confirmed_by is null
    and payments.deleted_at is null
    and exists (
        select 1 from public.orders o
        where o.id = payments.order_id
          and o.client_id = auth.uid()
          and o.deleted_at is null
    )
);

drop policy if exists payments_insert_staff on public.payments;
create policy payments_insert_staff
on public.payments for insert
with check (public.is_staff() and payments.confirmed_at is null);

drop policy if exists payments_read on public.payments;
create policy payments_read
on public.payments for select
using (
    public.is_staff()
    or (
        payments.deleted_at is null
        and exists (
            select 1 from public.orders o
            where o.id = payments.order_id
              and o.client_id = auth.uid()
        )
    )
);

drop policy if exists payments_confirm on public.payments;
create policy payments_confirm
on public.payments for update
using (public.is_staff())
with check (public.is_staff());

-- INVOICES
drop policy if exists invoices_read on public.invoices;
create policy invoices_read
on public.invoices for select
using (
    public.is_staff()
    or (
        invoices.deleted_at is null
        and exists (
            select 1 from public.orders o
            where o.id = invoices.order_id
              and o.client_id = auth.uid()
        )
    )
);

drop policy if exists invoices_staff_all on public.invoices;
create policy invoices_staff_all
on public.invoices for all
using (public.is_staff())
with check (public.is_staff());


-- ############################################################
-- PART 04 : ACCOUNTING / EMPLOYEE SCORES / AUDIT
-- ############################################################

-- ------------------------------------------------------------
-- CHART OF ACCOUNTS
-- ------------------------------------------------------------
create table if not exists public.accounts (
    code text primary key,
    name text not null,
    kind text not null
        check (kind in ('asset','liability','income','expense'))
);

insert into public.accounts (code, name, kind)
values
    ('1100','Bank','asset'),
    ('1200','Cash','asset'),
    ('1300','Receivables','asset'),
    ('2100','Payables','liability'),
    ('2200','Deferred Revenue','liability'),
    ('4100','Design Revenue','income'),
    ('4200','Web Revenue','income'),
    ('4300','Writing Revenue','income'),
    ('4400','Fines & Fees','income'),
    ('5100','Operating Expenses','expense'),
    ('5200','Salaries','expense'),
    ('5300','Subscriptions','expense'),
    ('5400','Taxes','expense')
on conflict (code) do nothing;

-- ------------------------------------------------------------
-- JOURNAL ENTRIES  (draft -> posted, posted = immutable)
-- ------------------------------------------------------------
create table if not exists public.journal_entries (
    id uuid primary key default gen_random_uuid(),
    entry_date date not null default current_date,
    memo text not null default '',
    source text not null default 'manual',
    source_id text not null default '',
    posted boolean not null default false,
    posted_at timestamptz,
    posted_by uuid references public.profiles(id),
    created_by uuid default auth.uid() references public.profiles(id),
    created_at timestamptz not null default now(),
    constraint journal_posted_consistent
        check (not posted or posted_at is not null)
);

-- for databases created from the old version
alter table public.journal_entries add column if not exists posted boolean not null default false;
alter table public.journal_entries add column if not exists posted_at timestamptz;
alter table public.journal_entries add column if not exists posted_by uuid references public.profiles(id);

create index if not exists idx_journal_entries_date   on public.journal_entries(entry_date);
create index if not exists idx_journal_entries_posted on public.journal_entries(posted);

-- ------------------------------------------------------------
-- JOURNAL LINES
-- ------------------------------------------------------------
create table if not exists public.journal_lines (
    id bigint generated always as identity primary key,
    entry_id uuid not null
        references public.journal_entries(id) on delete cascade,
    account_code text not null references public.accounts(code),
    debit numeric(12,2) not null default 0,
    credit numeric(12,2) not null default 0,
    constraint jl_positive_debit  check (debit >= 0),
    constraint jl_positive_credit check (credit >= 0),
    constraint jl_one_side        check (not (debit > 0 and credit > 0)),
    constraint jl_amount_required check (debit > 0 or credit > 0)
);

create index if not exists idx_journal_lines_entry   on public.journal_lines(entry_id);
create index if not exists idx_journal_lines_account on public.journal_lines(account_code);

-- ------------------------------------------------------------
-- IMMUTABILITY OF POSTED ENTRIES
-- ------------------------------------------------------------
create or replace function public.guard_posted_entry()
returns trigger
language plpgsql
as $$
begin
    if tg_op = 'DELETE' then
        if old.posted then
            raise exception 'Posted journal entries cannot be deleted';
        end if;
        return old;
    end if;

    if old.posted then
        raise exception 'Posted journal entries cannot be modified';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_guard_posted_entry on public.journal_entries;
create trigger trg_guard_posted_entry
before update or delete on public.journal_entries
for each row execute function public.guard_posted_entry();

create or replace function public.guard_posted_lines()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_entry  uuid;
    v_posted boolean;
begin
    if tg_op = 'UPDATE' and old.entry_id is distinct from new.entry_id then
        raise exception 'Journal line cannot be moved to another entry';
    end if;

    v_entry := case when tg_op = 'DELETE' then old.entry_id else new.entry_id end;

    select posted into v_posted
    from public.journal_entries
    where id = v_entry;

    -- entry already gone (cascade delete of a draft) -> allow
    if coalesce(v_posted, false) then
        raise exception 'Lines of a posted journal entry cannot be changed';
    end if;

    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_guard_posted_lines on public.journal_lines;
create trigger trg_guard_posted_lines
before insert or update or delete on public.journal_lines
for each row execute function public.guard_posted_lines();

-- ------------------------------------------------------------
-- POSTING ENGINE
--   post_journal_entry_system : internal, no auth check (triggers)
--   post_journal_entry        : public RPC, admin only (manual entries)
--   create_posted_entry       : internal, builds + posts an entry
-- ------------------------------------------------------------
create or replace function public.post_journal_entry_system(
    p_entry_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_posted boolean;
    v_count  integer;
    v_debit  numeric;
    v_credit numeric;
begin
    select posted into v_posted
    from public.journal_entries
    where id = p_entry_id
    for update;

    if not found then
        raise exception 'Journal entry not found';
    end if;

    if v_posted then
        raise exception 'Journal entry is already posted';
    end if;

    select count(*),
           coalesce(sum(debit), 0),
           coalesce(sum(credit), 0)
    into v_count, v_debit, v_credit
    from public.journal_lines
    where entry_id = p_entry_id;

    if v_count < 2 then
        raise exception 'Journal entry needs at least two lines';
    end if;

    if v_debit <> v_credit then
        raise exception 'Journal entry is not balanced (debit %, credit %)',
            v_debit, v_credit;
    end if;

    update public.journal_entries
    set posted    = true,
        posted_at = now(),
        posted_by = auth.uid()
    where id = p_entry_id;

    return true;
end;
$$;

revoke all on function public.post_journal_entry_system(uuid)
from public, anon, authenticated;

create or replace function public.post_journal_entry(
    p_entry_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Not allowed';
    end if;

    return public.post_journal_entry_system(p_entry_id);
end;
$$;

revoke all on function public.post_journal_entry(uuid) from public, anon, authenticated;
grant execute on function public.post_journal_entry(uuid) to authenticated;

-- p_lines: [{"account":"1100","debit":100,"credit":0}, ...]
create or replace function public.create_posted_entry(
    p_date      date,
    p_memo      text,
    p_source    text,
    p_source_id text,
    p_lines     jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id   uuid;
    v_line jsonb;
begin
    insert into public.journal_entries (entry_date, memo, source, source_id)
    values (coalesce(p_date, current_date), p_memo, p_source, p_source_id)
    returning id into v_id;

    for v_line in select * from jsonb_array_elements(p_lines)
    loop
        insert into public.journal_lines (entry_id, account_code, debit, credit)
        values (
            v_id,
            v_line->>'account',
            coalesce((v_line->>'debit')::numeric, 0),
            coalesce((v_line->>'credit')::numeric, 0)
        );
    end loop;

    perform public.post_journal_entry_system(v_id);

    return v_id;
end;
$$;

revoke all on function public.create_posted_entry(date,text,text,text,jsonb)
from public, anon, authenticated;

-- ------------------------------------------------------------
-- ACCOUNTING AUTOMATION
--   payment confirmed -> Dr Bank/Cash   Cr Deferred Revenue (or Fines)
--   order completed   -> Dr Deferred    Cr Revenue (by section)
--   expense inserted  -> Dr Expense     Cr Bank/Cash
--   salary paid       -> Dr Salaries    Cr Bank/Cash
-- Every automatic entry is created already balanced and posted,
-- and (payment/expense/salary) can be created only once per source.
-- ------------------------------------------------------------
create unique index if not exists idx_journal_source_unique
on public.journal_entries (source, source_id)
where source in ('payment','expense','salary');

-- revenue recognition: moves confirmed (non-fine) payments from
-- Deferred Revenue to the section revenue account, only for the
-- part not recognized yet.
create or replace function public.recognize_order_revenue(
    p_order_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order      record;
    v_received   numeric;
    v_recognized numeric;
    v_amount     numeric;
    v_account    text;
begin
    select id, section, status
    into v_order
    from public.orders
    where id = p_order_id;

    if not found or v_order.status <> 'completed' then
        return null;
    end if;

    select coalesce(sum(amount_mad), 0)
    into v_received
    from public.payments
    where order_id = p_order_id
      and confirmed_at is not null
      and deleted_at is null
      and kind <> 'fine';

    select coalesce(sum(l.debit), 0)
    into v_recognized
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    where e.source = 'order_revenue'
      and e.source_id = p_order_id
      and e.posted
      and l.account_code = '2200';

    v_amount := v_received - v_recognized;

    if v_amount <= 0 then
        return null;
    end if;

    v_account := case v_order.section
        when 'design'  then '4100'
        when 'web'     then '4200'
        else                '4300'
    end;

    return public.create_posted_entry(
        current_date,
        'Revenue recognition ' || p_order_id,
        'order_revenue',
        p_order_id,
        jsonb_build_array(
            jsonb_build_object('account','2200','debit',v_amount,'credit',0),
            jsonb_build_object('account',v_account,'debit',0,'credit',v_amount)
        )
    );
end;
$$;

revoke all on function public.recognize_order_revenue(text)
from public, anon, authenticated;

-- ---------- PAYMENTS ----------
create or replace function public.post_payment_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_status text;
begin
    if new.confirmed_at is not null and old.confirmed_at is null then

        perform public.create_posted_entry(
            new.confirmed_at::date,
            'Payment (' || new.kind || ') ' || new.order_id,
            'payment',
            new.id::text,
            jsonb_build_array(
                jsonb_build_object(
                    'account', case when new.method = 'cash' then '1200' else '1100' end,
                    'debit',   new.amount_mad,
                    'credit',  0
                ),
                jsonb_build_object(
                    'account', case when new.kind = 'fine' then '4400' else '2200' end,
                    'debit',   0,
                    'credit',  new.amount_mad
                )
            )
        );

        -- payment arriving after the order is completed
        if new.kind <> 'fine' then
            select status into v_status
            from public.orders where id = new.order_id;

            if v_status = 'completed' then
                perform public.recognize_order_revenue(new.order_id);
            end if;
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_payment_journal on public.payments;
create trigger trg_payment_journal
after update on public.payments
for each row execute function public.post_payment_journal();

-- ---------- ORDER COMPLETED ----------
create or replace function public.post_order_revenue_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'completed' and old.status is distinct from 'completed' then
        perform public.recognize_order_revenue(new.id);
    end if;
    return new;
end;
$$;

drop trigger if exists trg_orders_revenue_journal on public.orders;
create trigger trg_orders_revenue_journal
after update on public.orders
for each row execute function public.post_order_revenue_journal();

-- ---------- EXPENSES ----------
create table if not exists public.expenses (
    id uuid primary key default gen_random_uuid(),
    expense_date date not null default current_date,
    account_code text not null references public.accounts(code),
    description text not null default '',
    amount_mad numeric(12,2) not null check (amount_mad > 0),
    method text not null default 'bank'
        check (method in ('bank','cash')),
    receipt_path text,
    created_by uuid default auth.uid() references public.profiles(id),
    created_at timestamptz not null default now()
);

create index if not exists idx_expenses_date on public.expenses(expense_date);

create or replace function public.post_expense_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_kind text;
begin
    select kind into v_kind
    from public.accounts
    where code = new.account_code;

    if v_kind is distinct from 'expense' then
        raise exception 'Account % is not an expense account', new.account_code;
    end if;

    perform public.create_posted_entry(
        new.expense_date,
        'Expense: ' || new.description,
        'expense',
        new.id::text,
        jsonb_build_array(
            jsonb_build_object(
                'account', new.account_code,
                'debit',   new.amount_mad,
                'credit',  0
            ),
            jsonb_build_object(
                'account', case when new.method = 'cash' then '1200' else '1100' end,
                'debit',   0,
                'credit',  new.amount_mad
            )
        )
    );

    return new;
end;
$$;

drop trigger if exists trg_expense_journal on public.expenses;
create trigger trg_expense_journal
after insert on public.expenses
for each row execute function public.post_expense_journal();

-- ---------- SALARIES ----------
create table if not exists public.salary_payments (
    id uuid primary key default gen_random_uuid(),
    employee_id uuid not null references public.profiles(id),
    period_start date not null,
    period_end date not null,
    hours numeric(8,2) not null check (hours > 0),
    hourly_rate_mad numeric(10,2) not null check (hourly_rate_mad >= 0),
    amount_mad numeric(12,2) not null check (amount_mad > 0),
    method text not null default 'bank'
        check (method in ('bank','cash')),
    paid_at timestamptz not null default now(),
    created_by uuid default auth.uid() references public.profiles(id),
    created_at timestamptz not null default now(),
    constraint salary_period_valid check (period_end >= period_start)
);

create index if not exists idx_salary_employee on public.salary_payments(employee_id);

-- a worklog can be paid only once
alter table public.employee_worklogs
    add column if not exists salary_payment_id uuid
    references public.salary_payments(id);

create index if not exists idx_worklogs_salary
on public.employee_worklogs(salary_payment_id);

create or replace function public.guard_paid_worklog()
returns trigger
language plpgsql
as $$
begin
    if old.salary_payment_id is not null and (
        new.salary_payment_id is distinct from old.salary_payment_id
        or new.hours        is distinct from old.hours
        or new.work_date    is distinct from old.work_date
        or new.employee_id  is distinct from old.employee_id
        or new.order_id     is distinct from old.order_id
    ) then
        raise exception 'Worklogs already paid cannot be modified';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_guard_paid_worklog on public.employee_worklogs;
create trigger trg_guard_paid_worklog
before update on public.employee_worklogs
for each row execute function public.guard_paid_worklog();

create or replace function public.post_salary_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.create_posted_entry(
        new.paid_at::date,
        'Salary ' || new.employee_id::text || ' '
            || new.period_start::text || ' -> ' || new.period_end::text,
        'salary',
        new.id::text,
        jsonb_build_array(
            jsonb_build_object(
                'account', '5200',
                'debit',   new.amount_mad,
                'credit',  0
            ),
            jsonb_build_object(
                'account', case when new.method = 'cash' then '1200' else '1100' end,
                'debit',   0,
                'credit',  new.amount_mad
            )
        )
    );
    return new;
end;
$$;

drop trigger if exists trg_salary_journal on public.salary_payments;
create trigger trg_salary_journal
after insert on public.salary_payments
for each row execute function public.post_salary_journal();

-- admin pays approved, unpaid hours of a period at the current rate
create or replace function public.pay_salary(
    p_employee_id  uuid,
    p_period_start date,
    p_period_end   date,
    p_method       text default 'bank'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_rate   numeric;
    v_hours  numeric;
    v_amount numeric;
    v_id     uuid;
begin
    if not public.is_admin() then
        raise exception 'Not allowed';
    end if;

    if p_method not in ('bank','cash') then
        raise exception 'Invalid payment method';
    end if;

    if p_period_end < p_period_start then
        raise exception 'Invalid period';
    end if;

    if not exists (
        select 1 from public.profiles
        where id = p_employee_id and role in ('staff','admin')
    ) then
        raise exception 'Employee not found';
    end if;

    select hourly_rate_mad into v_rate
    from public.employee_private_data
    where employee_id = p_employee_id;

    if v_rate is null or v_rate <= 0 then
        raise exception 'Hourly rate is not set for this employee';
    end if;

    -- lock the rows so the same hours cannot be paid twice
    perform 1
    from public.employee_worklogs
    where employee_id = p_employee_id
      and work_date between p_period_start and p_period_end
      and approved_at is not null
      and salary_payment_id is null
    for update;

    select coalesce(sum(hours), 0) into v_hours
    from public.employee_worklogs
    where employee_id = p_employee_id
      and work_date between p_period_start and p_period_end
      and approved_at is not null
      and salary_payment_id is null;

    if v_hours <= 0 then
        raise exception 'No approved unpaid hours in this period';
    end if;

    v_amount := round(v_hours * v_rate, 2);

    insert into public.salary_payments (
        employee_id, period_start, period_end,
        hours, hourly_rate_mad, amount_mad, method
    )
    values (
        p_employee_id, p_period_start, p_period_end,
        v_hours, v_rate, v_amount, p_method
    )
    returning id into v_id;

    update public.employee_worklogs
    set salary_payment_id = v_id
    where employee_id = p_employee_id
      and work_date between p_period_start and p_period_end
      and approved_at is not null
      and salary_payment_id is null;

    return v_id;
end;
$$;

revoke all on function public.pay_salary(uuid,date,date,text)
from public, anon, authenticated;
grant execute on function public.pay_salary(uuid,date,date,text) to authenticated;

-- RLS for the new accounting tables
alter table public.expenses        enable row level security;
alter table public.salary_payments enable row level security;

drop policy if exists expenses_admin_read on public.expenses;
create policy expenses_admin_read
on public.expenses for select
using (public.is_admin());

drop policy if exists expenses_admin_insert on public.expenses;
create policy expenses_admin_insert
on public.expenses for insert
with check (public.is_admin());

-- no UPDATE / DELETE policy on expenses: corrections = new manual entry

drop policy if exists salary_admin_read on public.salary_payments;
create policy salary_admin_read
on public.salary_payments for select
using (public.is_admin());

drop policy if exists salary_self_read on public.salary_payments;
create policy salary_self_read
on public.salary_payments for select
using (employee_id = auth.uid());

-- no INSERT policy: salaries are created only through pay_salary()

-- ------------------------------------------------------------
-- EMPLOYEE SCORES
-- ------------------------------------------------------------
create table if not exists public.employee_scores (
    id uuid primary key default gen_random_uuid(),
    employee_id uuid not null references public.profiles(id),
    order_id text not null references public.orders(id) on delete cascade,
    contract_point integer not null default 1,
    manager_rating integer check (manager_rating between 1 and 10),
    client_rating integer check (client_rating between 1 and 5),
    created_at timestamptz not null default now(),
    unique (order_id, employee_id)
);

create index if not exists idx_scores_employee on public.employee_scores(employee_id);

-- manager rating can be set once; contract point never changes
create or replace function public.score_guard()
returns trigger
language plpgsql
as $$
begin
    if new.employee_id is distinct from old.employee_id
       or new.order_id is distinct from old.order_id then
        raise exception 'Score owner cannot be changed';
    end if;

    if old.manager_rating is not null
       and old.manager_rating is distinct from new.manager_rating then
        raise exception 'Manager rating cannot be changed';
    end if;

    if old.contract_point is distinct from new.contract_point then
        raise exception 'Contract point cannot be changed';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_score_guard on public.employee_scores;
create trigger trg_score_guard
before update on public.employee_scores
for each row execute function public.score_guard();

-- score rows are created automatically when an order is completed
create or replace function public.create_scores_on_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'completed' and old.status is distinct from 'completed' then
        insert into public.employee_scores (employee_id, order_id)
        select a.employee_id, a.order_id
        from public.order_assignments a
        where a.order_id = new.id
        on conflict (order_id, employee_id) do nothing;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_orders_create_scores on public.orders;
create trigger trg_orders_create_scores
after update on public.orders
for each row execute function public.create_scores_on_completion();

-- clients rate through this function only (no direct UPDATE policy)
create or replace function public.rate_employee(
    p_order_id text,
    p_employee_id uuid,
    p_rating integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_rating is null or p_rating not between 1 and 5 then
        raise exception 'Rating must be between 1 and 5';
    end if;

    if not exists (
        select 1 from public.orders o
        where o.id = p_order_id
          and o.client_id = auth.uid()
          and o.status = 'completed'
          and o.deleted_at is null
    ) then
        raise exception 'Not allowed';
    end if;

    update public.employee_scores
    set client_rating = p_rating
    where order_id = p_order_id
      and employee_id = p_employee_id;

    if not found then
        raise exception 'Score record not found';
    end if;

    return true;
end;
$$;

revoke all on function public.rate_employee(text,uuid,integer) from public, anon, authenticated;
grant execute on function public.rate_employee(text,uuid,integer) to authenticated;

-- ------------------------------------------------------------
-- AUDIT LOG
-- ------------------------------------------------------------
create table if not exists public.audit_log (
    id bigint generated always as identity primary key,
    actor_id uuid references public.profiles(id) on delete set null,
    action text not null,
    entity text not null,
    entity_id text not null default '',
    meta jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_audit_entity  on public.audit_log(entity, entity_id);
create index if not exists idx_audit_created on public.audit_log(created_at desc);

create or replace function public.create_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row jsonb;
begin
    if tg_op = 'DELETE' then
        v_row := to_jsonb(old);
    else
        v_row := to_jsonb(new);
    end if;

    insert into public.audit_log (actor_id, action, entity, entity_id, meta)
    values (
        auth.uid(),
        tg_op,
        tg_table_name,
        coalesce(v_row->>'id', v_row->>'code', v_row->>'employee_id', ''),
        case
            when tg_table_name = 'employee_private_data'
                then jsonb_build_object('redacted', true)
            else v_row - 'client_signature' - 'admin_signature'
        end
    );

    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

-- attach audit triggers (they were missing: the function was never used)
drop trigger if exists trg_audit_orders on public.orders;
create trigger trg_audit_orders
after insert or update or delete on public.orders
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_quotes on public.quotes;
create trigger trg_audit_quotes
after insert or update or delete on public.quotes
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_contracts on public.contracts;
create trigger trg_audit_contracts
after insert or update or delete on public.contracts
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_payments on public.payments;
create trigger trg_audit_payments
after insert or update or delete on public.payments
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_invoices on public.invoices;
create trigger trg_audit_invoices
after insert or update or delete on public.invoices
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_assignments on public.order_assignments;
create trigger trg_audit_assignments
after insert or update or delete on public.order_assignments
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_profiles on public.profiles;
create trigger trg_audit_profiles
after update or delete on public.profiles
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_journal_entries on public.journal_entries;
create trigger trg_audit_journal_entries
after insert or update or delete on public.journal_entries
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_private_data on public.employee_private_data;
create trigger trg_audit_private_data
after insert or update or delete on public.employee_private_data
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_expenses on public.expenses;
create trigger trg_audit_expenses
after insert or update or delete on public.expenses
for each row execute function public.create_audit_log();

drop trigger if exists trg_audit_salary on public.salary_payments;
create trigger trg_audit_salary
after insert or update or delete on public.salary_payments
for each row execute function public.create_audit_log();

-- ------------------------------------------------------------
-- EMPLOYEE VIEWS (security_invoker: RLS of the caller applies)
-- ------------------------------------------------------------
-- dropped first: a column was renamed (avg_entry_hours -> avg_hours_per_project)
drop view if exists public.v_employee_hours;

create view public.v_employee_hours
with (security_invoker = true)
as
select
    p.id,
    p.full_name,
    count(distinct w.order_id) as projects,
    sum(w.hours) as total_hours,
    sum(w.hours) filter (where w.approved_at is not null) as approved_hours,
    sum(w.hours) filter (
        where w.approved_at is not null and w.salary_payment_id is null
    ) as unpaid_approved_hours,
    round(
        sum(w.hours) / greatest(count(distinct w.order_id), 1),
        2
    ) as avg_hours_per_project
from public.employee_worklogs w
join public.profiles p on p.id = w.employee_id
group by p.id, p.full_name;

create or replace view public.v_employee_leaderboard
with (security_invoker = true)
as
select
    p.id,
    p.full_name,
    count(*) as contracts_done,
    sum(s.contract_point) as points,
    avg(s.manager_rating) as avg_manager,
    avg(s.client_rating) as avg_client
from public.employee_scores s
join public.profiles p on p.id = s.employee_id
group by p.id, p.full_name
order by points desc;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table public.accounts        enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines   enable row level security;
alter table public.employee_scores enable row level security;
alter table public.audit_log       enable row level security;

-- ACCOUNTS
drop policy if exists accounts_read on public.accounts;
create policy accounts_read
on public.accounts for select
using (public.is_staff());

drop policy if exists accounts_admin_all on public.accounts;
create policy accounts_admin_all
on public.accounts for all
using (public.is_admin())
with check (public.is_admin());

-- JOURNAL ENTRIES
-- (no UPDATE policy on purpose: posting goes through post_journal_entry())
drop policy if exists journal_entries_admin on public.journal_entries;
create policy journal_entries_admin
on public.journal_entries for select
using (public.is_admin());

drop policy if exists journal_entries_admin_insert on public.journal_entries;
create policy journal_entries_admin_insert
on public.journal_entries for insert
with check (public.is_admin() and posted = false);

drop policy if exists journal_entries_admin_delete on public.journal_entries;
create policy journal_entries_admin_delete
on public.journal_entries for delete
using (public.is_admin() and posted = false);

-- JOURNAL LINES
drop policy if exists journal_lines_admin on public.journal_lines;
create policy journal_lines_admin
on public.journal_lines for select
using (public.is_admin());

drop policy if exists journal_lines_admin_insert on public.journal_lines;
create policy journal_lines_admin_insert
on public.journal_lines for insert
with check (public.is_admin());

drop policy if exists journal_lines_admin_update on public.journal_lines;
create policy journal_lines_admin_update
on public.journal_lines for update
using (public.is_admin())
with check (public.is_admin());

drop policy if exists journal_lines_admin_delete on public.journal_lines;
create policy journal_lines_admin_delete
on public.journal_lines for delete
using (public.is_admin());

-- EMPLOYEE SCORES (clients have no direct access: use rate_employee())
drop policy if exists employee_scores_admin on public.employee_scores;
create policy employee_scores_admin
on public.employee_scores for all
using (public.is_admin())
with check (public.is_admin());

drop policy if exists employee_scores_staff_read on public.employee_scores;
create policy employee_scores_staff_read
on public.employee_scores for select
using (public.is_staff());

drop policy if exists employee_scores_client_update on public.employee_scores;

-- AUDIT LOG (read-only for admin; written only by trigger)
drop policy if exists audit_log_admin on public.audit_log;
create policy audit_log_admin
on public.audit_log for select
using (public.is_admin());


-- ############################################################
-- PART 05 : STORAGE / BLOCKED TIMES / REPORTS / SEEDS
-- ############################################################

-- ------------------------------------------------------------
-- BLOCKED TIMES
-- ------------------------------------------------------------
create table if not exists public.blocked_times (
    id uuid primary key default gen_random_uuid(),
    weekday integer not null check (weekday between 0 and 6),
    start_hour integer not null check (start_hour between 0 and 23),
    end_hour integer not null check (end_hour between 0 and 24),
    reason text not null default '',
    active boolean not null default true,
    constraint blocked_hours_order check (end_hour > start_hour)
);

create index if not exists idx_blocked_times_active on public.blocked_times(active);

alter table public.blocked_times enable row level security;

drop policy if exists blocked_times_read on public.blocked_times;
create policy blocked_times_read
on public.blocked_times for select
using (true);

drop policy if exists blocked_times_admin on public.blocked_times;
create policy blocked_times_admin
on public.blocked_times for all
using (public.is_admin())
with check (public.is_admin());

-- ------------------------------------------------------------
-- STORAGE BUCKETS
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values
    ('order-files',  'order-files',  false),
    ('receipts',     'receipts',     false),
    ('deliverables', 'deliverables', false)
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- STORAGE POLICIES
-- PATH FORMAT (first folder = ORDER ID):
--   order-files/MAK-2027-0001/file.pdf
--   receipts/MAK-2027-0001/payment.jpg
--   deliverables/MAK-2027-0001/work.zip
-- ------------------------------------------------------------
drop policy if exists storage_upload_client        on storage.objects;
drop policy if exists storage_read                 on storage.objects;
drop policy if exists storage_deliverables_upload  on storage.objects;
drop policy if exists storage_deliverables_update  on storage.objects;
drop policy if exists mak_storage_insert           on storage.objects;
drop policy if exists mak_storage_select           on storage.objects;
drop policy if exists mak_storage_update           on storage.objects;
drop policy if exists mak_storage_delete           on storage.objects;

-- upload: clients -> order-files / receipts of their own order
--         staff   -> any of the three buckets
create policy mak_storage_insert
on storage.objects for insert
to authenticated
with check (
    bucket_id in ('order-files','receipts','deliverables')
    and exists (
        select 1 from public.orders o
        where o.id = (storage.foldername(name))[1]
          and (
              public.is_staff()
              or (
                  o.client_id = auth.uid()
                  and o.deleted_at is null
                  and bucket_id in ('order-files','receipts')
              )
          )
    )
);

-- read: order owner or staff
create policy mak_storage_select
on storage.objects for select
to authenticated
using (
    bucket_id in ('order-files','receipts','deliverables')
    and exists (
        select 1 from public.orders o
        where o.id = (storage.foldername(name))[1]
          and (
              public.is_staff()
              or (
                  o.client_id = auth.uid()
                  and o.deleted_at is null
                  and (
                      bucket_id <> 'deliverables'
                      or o.status in ('paid','delivered','completed')
                  )
              )
          )
    )
);

-- update / delete: staff only
create policy mak_storage_update
on storage.objects for update
to authenticated
using (
    bucket_id in ('order-files','receipts','deliverables')
    and public.is_staff()
)
with check (
    bucket_id in ('order-files','receipts','deliverables')
    and public.is_staff()
);

create policy mak_storage_delete
on storage.objects for delete
to authenticated
using (
    bucket_id in ('order-files','receipts','deliverables')
    and public.is_staff()
);

-- ------------------------------------------------------------
-- FINANCIAL REPORTS  (posted entries only, caller's RLS applies)
-- ------------------------------------------------------------
create or replace view public.v_monthly_pnl
with (security_invoker = true)
as
select
    date_trunc('month', e.entry_date)::date as month,
    coalesce(sum(l.credit) filter (where a.kind = 'income'), 0) as income_mad,
    coalesce(sum(l.debit)  filter (where a.kind = 'expense'), 0) as expense_mad,
    coalesce(sum(l.credit) filter (where a.kind = 'income'), 0)
  - coalesce(sum(l.debit)  filter (where a.kind = 'expense'), 0) as profit_mad
from public.journal_entries e
join public.journal_lines l on l.entry_id = e.id
join public.accounts a      on a.code = l.account_code
where e.posted
group by 1
order by 1 desc;

create or replace view public.v_cash_balance
with (security_invoker = true)
as
select
    a.code,
    a.name,
    coalesce(sum(l.debit - l.credit), 0) as balance_mad
from public.accounts a
left join (
    select jl.account_code, jl.debit, jl.credit
    from public.journal_lines jl
    join public.journal_entries je on je.id = jl.entry_id
    where je.posted
) l on l.account_code = a.code
where a.kind = 'asset'
group by a.code, a.name
order by a.code;

-- ------------------------------------------------------------
-- CONTRACT SEEDS
-- ------------------------------------------------------------
insert into public.contract_templates (section, title, body_ar, body_en)
values
(
    'design',
    'عقد خدمة تصميم M.A.K',
    'عقد تقديم خدمة تصميم بين M.A.K والعميل.
يلتزم المنفذ بتنفيذ العمل حسب الوصف الوارد في الطلب.
يلتزم العميل بتوفير المعلومات المطلوبة.
العربون غير مسترجع عند الإلغاء بعد بدء التنفيذ.
التعديلات المجانية خلال الفترة المحددة بالنظام.
جميع الملفات النهائية تسلم بعد السداد الكامل.
يقر الطرفان بسرية المعلومات المتبادلة.
تسوى النزاعات وفق القوانين المحلية.',
    'Design service agreement between M.A.K and the client.
Work shall be delivered according to the approved order.
The client shall provide required information.
Deposits are non-refundable after execution starts.
Free revisions apply within the allowed revision window.
Final files are released after full payment.
Both parties shall maintain confidentiality.
Disputes are subject to applicable local laws.'
),
(
    'web',
    'عقد خدمة برمجة M.A.K',
    'عقد تطوير وبرمجة بين M.A.K والعميل.
يشمل النطاق المواصفات المعتمدة داخل الطلب.
أي تغيير جوهري يعد طلباً إضافياً.
يتم تسليم نسخة معاينة قبل التسليم النهائي.
تنقل حقوق الاستخدام بعد السداد الكامل.
يلتزم الطرفان بالسرية والخصوصية.
تطبق سياسة الإلغاء والتعديلات الخاصة بالنظام.',
    'Software development agreement between M.A.K and the client.
The scope is limited to approved specifications.
Major scope changes are treated as additional work.
A preview version is delivered before final release.
Usage rights transfer after full payment.
Both parties agree to confidentiality.
Cancellation and revision policies follow platform rules.'
),
(
    'writing',
    'عقد خدمة كتابة M.A.K',
    'عقد كتابة وتأليف وترجمة بين M.A.K والعميل.
ينفذ العمل وفق اللغة والمواصفات المطلوبة.
يضمن المنفذ أصالة المحتوى المنتج.
يمنع إعادة توزيع المحتوى قبل السداد الكامل.
التعديلات وفق سياسة النظام.
تطبق بنود السرية وحماية البيانات.',
    'Writing and translation agreement between M.A.K and the client.
Work is delivered according to requested language and specifications.
The provider guarantees originality of produced content.
Redistribution before full payment is prohibited.
Revisions follow the platform policy.
Confidentiality and data protection clauses apply.'
)
on conflict (section, title) do nothing;

-- ============================================================
-- END OF SCHEMA V3 FINAL (FIXED)
-- ============================================================
