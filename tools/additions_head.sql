-- ============================================================
-- M.A.K BOOKING V2 — ADDITIONS  (يُشغَّل بعد mak_booking_v3_fixed.sql)
-- لا يغيّر أي شيء يعمل في v3؛ يضيف فقط. آمن لإعادة التشغيل (idempotent).
--
-- يضيف:
--  1) أعمدة إعدادات الشركة (مدينة، واتساب، نسب العربون/الغرامة/التعديل)
--  2) price_tiers: أربع فئات أسعار (150/350/700/950) قابلة للتعديل
--  3) staff_permissions: من يحق له تعديل الأسعار من الموظفين
--  4) brief_questions: أسئلة البريف قابلة للتحرير
--  5) order_change_requests: طلبات التعديل والإلغاء
--  6) ملاحق العقود (parent_contract_id) + السماح بتوقيعها أثناء التنفيذ
--  7) حراس: مكوّن السعر المتغير للمدير فقط، الغرامات للمدير فقط
--  8) تحويل الطلب إلى PAID تلقائياً عند اكتمال الدفع + إشعارات
--  9) bucket "previews" للمعاينات بعلامة مائية
-- 10) انتهاء صلاحية العروض expire_quotes()
-- 11) تفعيل Realtime للجداول المهمة
-- 12) قوالب العقد الكاملة  13) أسئلة البريف الثلاثون
-- ============================================================


-- ------------------------------------------------------------
-- 1) COMPANY SETTINGS
-- ------------------------------------------------------------
alter table public.company_settings add column if not exists whatsapp text not null default '';
alter table public.company_settings add column if not exists city text not null default '';
alter table public.company_settings add column if not exists deposit_percent integer not null default 10 check (deposit_percent between 0 and 100);
alter table public.company_settings add column if not exists cancel_fine_percent integer not null default 10 check (cancel_fine_percent between 0 and 100);
alter table public.company_settings add column if not exists modify_fee_percent integer not null default 5 check (modify_fee_percent between 0 and 100);
alter table public.company_settings add column if not exists revision_rounds integer not null default 2 check (revision_rounds >= 0);


-- ------------------------------------------------------------
-- 3) STAFF PERMISSIONS (قبل الأسعار لأن سياساتها تعتمد عليها)
-- ------------------------------------------------------------
create table if not exists public.staff_permissions (
    employee_id uuid primary key references public.profiles(id) on delete cascade,
    can_edit_prices boolean not null default false,
    updated_at timestamptz not null default now()
);

alter table public.staff_permissions enable row level security;

drop policy if exists staff_permissions_admin on public.staff_permissions;
create policy staff_permissions_admin on public.staff_permissions
for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists staff_permissions_self on public.staff_permissions;
create policy staff_permissions_self on public.staff_permissions
for select using (employee_id = auth.uid());

create or replace function public.can_edit_prices()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.is_admin() or exists (
        select 1 from public.staff_permissions sp
        join public.profiles p on p.id = sp.employee_id
        where sp.employee_id = auth.uid()
          and sp.can_edit_prices
          and p.active
          and p.role = 'staff'
    );
$$;


-- ------------------------------------------------------------
-- 2) PRICE TIERS
-- ------------------------------------------------------------
create table if not exists public.price_tiers (
    code text primary key check (code in ('small','medium','large','premium')),
    label_ar text not null,
    label_en text not null,
    price_mad integer not null check (price_mad >= 0),
    sort integer not null default 0,
    updated_at timestamptz not null default now()
);

insert into public.price_tiers (code, label_ar, label_en, price_mad, sort) values
    ('small',   'صغير',  'Small',   150, 1),
    ('medium',  'متوسط', 'Medium',  350, 2),
    ('large',   'كبير',  'Large',   700, 3),
    ('premium', 'مميّز', 'Premium', 950, 4)
on conflict (code) do nothing;

drop trigger if exists trg_price_tiers_updated on public.price_tiers;
create trigger trg_price_tiers_updated before update on public.price_tiers
for each row execute function public.touch_updated_at();

alter table public.price_tiers enable row level security;

drop policy if exists price_tiers_read on public.price_tiers;
create policy price_tiers_read on public.price_tiers
for select to authenticated using (true);

-- المدير أو موظف مخوَّل: تعديل السعر فقط (لا إضافة ولا حذف)
drop policy if exists price_tiers_update on public.price_tiers;
create policy price_tiers_update on public.price_tiers
for update using (public.can_edit_prices()) with check (public.can_edit_prices());

drop policy if exists price_tiers_admin_all on public.price_tiers;
create policy price_tiers_admin_all on public.price_tiers
for all using (public.is_admin()) with check (public.is_admin());


-- ------------------------------------------------------------
-- 4) BRIEF QUESTIONS
-- ------------------------------------------------------------
create table if not exists public.brief_questions (
    key text primary key,
    grp text not null default '',
    label_ar text not null,
    label_en text not null default '',
    type text not null default 'text'
        check (type in ('text','longtext','choice','multi','date')),
    options jsonb not null default '[]'::jsonb,
    active boolean not null default true,
    sort integer not null default 0
);

alter table public.brief_questions enable row level security;

drop policy if exists brief_questions_read on public.brief_questions;
create policy brief_questions_read on public.brief_questions
for select to authenticated using (true);

drop policy if exists brief_questions_admin on public.brief_questions;
create policy brief_questions_admin on public.brief_questions
for all using (public.is_admin()) with check (public.is_admin());


-- ------------------------------------------------------------
-- 5) CHANGE REQUESTS (تعديل / إلغاء)
-- ------------------------------------------------------------
create table if not exists public.order_change_requests (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders(id) on delete cascade,
    kind text not null check (kind in ('cancel','modify')),
    note text not null default '',
    status text not null default 'pending'
        check (status in ('pending','approved','rejected')),
    fee_mad integer not null default 0 check (fee_mad >= 0),
    created_by uuid default auth.uid() references public.profiles(id),
    resolved_by uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    resolved_at timestamptz
);

create index if not exists idx_change_requests_order on public.order_change_requests(order_id);

alter table public.order_change_requests enable row level security;

drop policy if exists change_requests_insert_client on public.order_change_requests;
create policy change_requests_insert_client on public.order_change_requests
for insert with check (
    status = 'pending' and fee_mad = 0
    and exists (
        select 1 from public.orders o
        where o.id = order_change_requests.order_id
          and o.client_id = auth.uid() and o.deleted_at is null
    )
);

drop policy if exists change_requests_select on public.order_change_requests;
create policy change_requests_select on public.order_change_requests
for select using (
    public.is_staff() or exists (
        select 1 from public.orders o
        where o.id = order_change_requests.order_id and o.client_id = auth.uid()
    )
);

drop policy if exists change_requests_update_staff on public.order_change_requests;
create policy change_requests_update_staff on public.order_change_requests
for update using (public.is_staff()) with check (public.is_staff());

-- الإلغاء والرسوم: للمدير فقط
create or replace function public.guard_change_request()
returns trigger
language plpgsql
as $$
begin
    if auth.uid() is not null and tg_op = 'UPDATE' then
        if new.kind is distinct from old.kind or new.order_id is distinct from old.order_id then
            raise exception 'Change request identity cannot be changed';
        end if;
        if (new.status is distinct from old.status or new.fee_mad is distinct from old.fee_mad)
           and not public.is_admin()
           and (new.kind = 'cancel' or new.fee_mad > 0) then
            raise exception 'Only admin can resolve cancellations or set fees';
        end if;
        if new.status is distinct from old.status and new.status <> 'pending' then
            new.resolved_at := now();
            new.resolved_by := auth.uid();
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_guard_change_request on public.order_change_requests;
create trigger trg_guard_change_request before update on public.order_change_requests
for each row execute function public.guard_change_request();

create or replace function public.notify_change_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
    for r in select id from public.profiles where role in ('staff','admin') and active loop
        perform public.create_notification(
            r.id, 'system',
            case when new.kind = 'cancel' then 'طلب إلغاء' else 'طلب تعديل' end,
            'طلب جديد على ' || new.order_id, '/orders/' || new.order_id
        );
    end loop;
    return new;
end;
$$;

drop trigger if exists trg_notify_change_request on public.order_change_requests;
create trigger trg_notify_change_request after insert on public.order_change_requests
for each row execute function public.notify_change_request();


-- ------------------------------------------------------------
-- 6) CONTRACT ADDENDA
-- ------------------------------------------------------------
alter table public.contracts add column if not exists kind text not null default 'main'
    check (kind in ('main','addendum'));
alter table public.contracts add column if not exists parent_contract_id text
    references public.contracts(id);

create index if not exists idx_contract_parent on public.contracts(parent_contract_id);

-- توقيع العميل: يُسمح للملحق أثناء التنفيذ (العقد الأصلي لا يتغير)
create or replace function public.sign_contract(p_contract_id text, p_signature text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_contract public.contracts%rowtype;
    v_admin    record;
begin
    if auth.uid() is null then raise exception 'Not authenticated'; end if;
    if coalesce(btrim(p_signature), '') = '' then raise exception 'Signature is required'; end if;

    select * into v_contract from public.contracts
    where id = p_contract_id and deleted_at is null for update;
    if not found then raise exception 'Contract not found'; end if;

    if not exists (
        select 1 from public.orders o
        where o.id = v_contract.order_id and o.client_id = auth.uid()
    ) then raise exception 'Not allowed'; end if;

    if v_contract.status <> 'awaiting_client' then
        raise exception 'Contract is not awaiting the client signature';
    end if;

    if not exists (
        select 1 from public.orders o
        where o.id = v_contract.order_id and o.deleted_at is null
          and (
              o.status in ('accepted','contract_pending')
              or (v_contract.parent_contract_id is not null
                  and o.status in ('in_progress','preview_sent','paid','delivered'))
          )
    ) then raise exception 'Order is not in a state that allows contract signing'; end if;

    perform set_config('app.contract_sign', 'on', true);
    update public.contracts
    set client_signature = p_signature, status = 'awaiting_admin'
    where id = p_contract_id;
    perform set_config('app.contract_sign', 'off', true);

    for v_admin in select id from public.profiles where role = 'admin' and active loop
        perform public.create_notification(
            v_admin.id, 'contract', 'عقد بانتظار توقيع المدير',
            'يوجد عقد جديد يحتاج الاعتماد', '/contracts/' || p_contract_id
        );
    end loop;
    return true;
end;
$$;

create or replace function public.admin_sign_contract(p_contract_id text, p_signature text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_contract public.contracts%rowtype;
begin
    if not public.is_admin() then raise exception 'Not allowed'; end if;
    if coalesce(btrim(p_signature), '') = '' then raise exception 'Signature is required'; end if;

    select * into v_contract from public.contracts
    where id = p_contract_id and deleted_at is null for update;
    if not found then raise exception 'Contract not found'; end if;

    if v_contract.status <> 'awaiting_admin' or v_contract.client_signature is null then
        raise exception 'Contract is not awaiting the admin signature';
    end if;

    if not exists (
        select 1 from public.orders o
        where o.id = v_contract.order_id and o.deleted_at is null
          and (
              o.status in ('accepted','contract_pending')
              or (v_contract.parent_contract_id is not null
                  and o.status in ('in_progress','preview_sent','paid','delivered'))
          )
    ) then raise exception 'Order is not in a state that allows contract signing'; end if;

    perform set_config('app.contract_sign', 'on', true);
    update public.contracts
    set admin_signature = p_signature, status = 'signed', signed_at = now()
    where id = p_contract_id;
    perform set_config('app.contract_sign', 'off', true);
    return true;
end;
$$;

revoke all on function public.sign_contract(text,text)       from public, anon, authenticated;
revoke all on function public.admin_sign_contract(text,text) from public, anon, authenticated;
grant execute on function public.sign_contract(text,text)       to authenticated;
grant execute on function public.admin_sign_contract(text,text) to authenticated;

-- إشعار العميل عند وصول عقد للتوقيع
create or replace function public.notify_contract_awaiting_client()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_client uuid;
begin
    if new.status = 'awaiting_client' and old.status is distinct from 'awaiting_client' then
        select client_id into v_client from public.orders where id = new.order_id;
        perform public.create_notification(
            v_client, 'contract', 'عقد بانتظار توقيعك',
            'تم تجهيز العقد ' || new.id || ' لطلبك ' || new.order_id, '/contracts/' || new.id
        );
    end if;
    return new;
end;
$$;

drop trigger if exists trg_contract_awaiting_client on public.contracts;
create trigger trg_contract_awaiting_client after update on public.contracts
for each row execute function public.notify_contract_awaiting_client();


-- فريق الطلب: العميل يرى أسماء فريق طلبه (ويقيّمهم) دون فتح جدول profiles
create or replace function public.order_team(p_order_id text)
returns table (
    employee_id uuid, full_name text, role text,
    client_rating integer, manager_rating integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not (
        public.is_staff()
        or exists (
            select 1 from public.orders o
            where o.id = p_order_id and o.client_id = auth.uid() and o.deleted_at is null
        )
    ) then
        raise exception 'Not allowed';
    end if;

    return query
    select a.employee_id, p.full_name, a.role,
           s.client_rating,
           case when public.is_staff() then s.manager_rating else null end
    from public.order_assignments a
    join public.profiles p on p.id = a.employee_id
    left join public.employee_scores s
           on s.order_id = a.order_id and s.employee_id = a.employee_id
    where a.order_id = p_order_id;
end;
$$;

revoke all on function public.order_team(text) from public, anon;
grant execute on function public.order_team(text) to authenticated;


-- ------------------------------------------------------------
-- 7) GUARDS
-- ------------------------------------------------------------
-- الموظف (غير المدير) لا يرسل/يعتمد عرضاً فيه مكوّن سعر متغير
create or replace function public.guard_quote_delta()
returns trigger
language plpgsql
as $$
begin
    if auth.uid() is not null and public.is_staff() and not public.is_admin() then
        if new.status in ('approved','sent') and new.variable_delta_mad <> 0 then
            raise exception 'Variable price changes require admin approval';
        end if;
        if tg_op = 'INSERT' then
            if new.approved_by is not null then
                raise exception 'Only admin can approve quotes';
            end if;
        elsif new.approved_by is distinct from old.approved_by then
            raise exception 'Only admin can approve quotes';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_guard_quote_delta on public.quotes;
create trigger trg_guard_quote_delta before insert or update on public.quotes
for each row execute function public.guard_quote_delta();

-- الغرامات: المدير فقط
create or replace function public.guard_payment_insert()
returns trigger
language plpgsql
as $$
begin
    if auth.uid() is not null and new.kind = 'fine' and not public.is_admin() then
        raise exception 'Only admin can add fines';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_payment_insert_guard on public.payments;
create trigger trg_payment_insert_guard before insert on public.payments
for each row execute function public.guard_payment_insert();


-- ------------------------------------------------------------
-- 8) PAID AUTOMATICALLY + NEW ORDER NOTIFICATION
-- ------------------------------------------------------------
create or replace function public.payment_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order public.orders%rowtype;
    v_paid  numeric;
begin
    if new.confirmed_at is not null and old.confirmed_at is null and new.kind <> 'fine' then
        select * into v_order from public.orders where id = new.order_id;
        select coalesce(sum(amount_mad), 0) into v_paid
        from public.payments
        where order_id = new.order_id and confirmed_at is not null
          and deleted_at is null and kind <> 'fine';

        if v_order.total_mad > 0 and v_paid >= v_order.total_mad then
            update public.orders set status = 'paid'
            where id = new.order_id and status in ('in_progress','preview_sent');
            update public.invoices set status = 'paid'
            where order_id = new.order_id and status = 'issued';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_payment_paid_status on public.payments;
create trigger trg_payment_paid_status after update on public.payments
for each row execute function public.payment_paid_status();

create or replace function public.notify_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
    for r in select id from public.profiles where role in ('staff','admin') and active loop
        perform public.create_notification(
            r.id, 'system', 'طلب جديد', 'وصل طلب جديد ' || new.id, '/orders/' || new.id
        );
    end loop;
    return new;
end;
$$;

drop trigger if exists trg_new_order_notify on public.orders;
create trigger trg_new_order_notify after insert on public.orders
for each row execute function public.notify_new_order();


-- ------------------------------------------------------------
-- 9) STORAGE: PREVIEWS (معاينات بعلامة مائية — يراها العميل قبل الدفع)
-- PATH: previews/MAK-2026-0001/file.png
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('previews', 'previews', false)
on conflict (id) do nothing;

drop policy if exists mak_previews_insert on storage.objects;
create policy mak_previews_insert on storage.objects
for insert to authenticated
with check (bucket_id = 'previews' and public.is_staff());

drop policy if exists mak_previews_select on storage.objects;
create policy mak_previews_select on storage.objects
for select to authenticated
using (
    bucket_id = 'previews'
    and exists (
        select 1 from public.orders o
        where o.id = (storage.foldername(name))[1]
          and (public.is_staff() or (o.client_id = auth.uid() and o.deleted_at is null))
    )
);

drop policy if exists mak_previews_update on storage.objects;
create policy mak_previews_update on storage.objects
for update to authenticated
using (bucket_id = 'previews' and public.is_staff())
with check (bucket_id = 'previews' and public.is_staff());

drop policy if exists mak_previews_delete on storage.objects;
create policy mak_previews_delete on storage.objects
for delete to authenticated
using (bucket_id = 'previews' and public.is_staff());


-- ------------------------------------------------------------
-- 10) QUOTE EXPIRY
-- يستدعيها التطبيق عند فتح لوحة الموظف/المدير؛ ويمكن جدولتها بـ pg_cron يومياً.
-- ------------------------------------------------------------
create or replace function public.expire_quotes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_count integer;
begin
    if auth.uid() is not null and not public.is_staff() then
        raise exception 'Not allowed';
    end if;

    with expired as (
        update public.quotes set status = 'expired'
        where status = 'sent' and valid_until is not null and valid_until < current_date
        returning order_id
    )
    update public.orders set status = 'expired'
    where status = 'quoted' and id in (select order_id from expired);

    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

revoke all on function public.expire_quotes() from public, anon;
grant execute on function public.expire_quotes() to authenticated;


-- ------------------------------------------------------------
-- 11) REALTIME
-- ------------------------------------------------------------
do $$
declare t text;
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        foreach t in array array[
            'orders','quotes','contracts','payments','invoices',
            'messages','notifications','order_change_requests'
        ] loop
            if not exists (
                select 1 from pg_publication_tables
                where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
            ) then
                execute format('alter publication supabase_realtime add table public.%I', t);
            end if;
        end loop;
    end if;
end;
$$;
