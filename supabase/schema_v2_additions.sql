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

-- ------------------------------------------------------------
-- 12) قوالب العقد الكاملة (15 مادة، عربي + إنجليزي) — تحدّث القوالب القصيرة في v3
--     المتغيرات {{...}} تُستبدل عند إنشاء العقد من التطبيق.
-- ------------------------------------------------------------
insert into public.contract_templates (section, title, body_ar, body_en)
values
('design', 'عقد خدمة تصميم M.A.K', $mak$عقد خدمة رقم {{CONTRACT_ID}}
المرتبط بالطلب رقم {{ORDER_ID}} — بتاريخ {{DATE}}

بين الطرفين:
الطرف الأول («M.A.K»): {{COMPANY_NAME}} — المدينة: {{COMPANY_CITY}} — البريد: {{COMPANY_EMAIL}}.
الطرف الثاني («العميل»): {{CLIENT_NAME}} — البريد: {{CLIENT_EMAIL}}.

المادة 1 — التعريفات والأطراف
«الطلب»: طلب الخدمة المسجّل في التطبيق برقم {{ORDER_ID}} بما فيه البريف والخيارات المعتمدة. «المعاينة»: نسخة عمل بعلامة مائية لا تصلح للاستخدام التجاري. «النسخة النهائية»: الملفات الخالية من العلامة المائية التي تُسلَّم بعد السداد الكامل. «ملحق»: وثيقة مكتوبة وموقّعة من الطرفين تعدّل هذا العقد. «بدء التنفيذ»: لحظة توقيع الطرفين على هذا العقد وإرسال إشعار بدء التنفيذ إلى العميل داخل التطبيق.

المادة 2 — نطاق العمل
تلتزم M.A.K بتنفيذ الخدمة الموصوفة في الطلب والخيارات المعتمدة فقط: {{SCOPE}}. {{SECTION_NOTE}} أي عمل خارج هذا النطاق يتطلب ملحقاً موقّعاً يحدد السعر والمدة. تشمل الخدمة عدد جولات مراجعة قدره {{REVISIONS}} جولات؛ وما زاد عنها يُعامَل كتعديل مدفوع وفق المادة 5.

المادة 3 — الأصالة والملكية الفكرية
تضمن M.A.K أن العمل المسلَّم من إنتاجها أو مرخّص لها قانونياً، وأنه لا ينتهك حقوق طرف ثالث بعلمها. الخطوط والصور والعناصر المرخّصة من طرف ثالث: مسؤولية الترخيص على M.A.K إن قدّمتها هي، وعلى العميل إن قدّمها هو. تنتقل حقوق استخدام النسخة النهائية إلى العميل بعد السداد الكامل فقط، وقبل ذلك تبقى الحقوق لـ M.A.K ولا يجوز استخدام غير المعاينة بعلامتها المائية. حق الاستخدام حصري أو غير حصري حسب ما يُنص عليه في الطلب أو الملحق، وتحتفظ M.A.K بحقها المعنوي كمؤلف للعمل.

المادة 4 — المقابل والدفع
القيمة الإجمالية للعقد {{TOTAL}}. عربون {{DEPOSIT}} يُدفع عند توقيع العقد، والباقي حسب الاتفاق قبل تسليم النسخة النهائية. الدفع بالتحويل البنكي إلى الحساب المعلن للشركة داخل التطبيق، ويُعدّ الدفع مكتملاً بتأكيد M.A.K استلام المبلغ. لا تُسلَّم النسخة النهائية قبل اكتمال السداد ما لم يُتفق كتابياً على الدفع عند التسليم.

المادة 5 — نافذة الثلاثة أيام والتعديلات
تبدأ نافذة الثلاثة (3) أيام من بدء التنفيذ؛ خلالها يحق للعميل طلب التعديل أو الإلغاء مجاناً (مع مراعاة المادة 6). بعد انتهائها يخضع كل تعديل لزيادة قدرها {{MODIFY_FEE}}% من قيمة العقد على الأقل، وتحدد M.A.K النسبة النهائية (من 5% إلى 10%) حسب حجم التعديل، وتُعتمد بملحق موقّع قبل البدء به.

المادة 6 — الإلغاء
قبل بدء التنفيذ: يُسترد العربون كاملاً. بعد بدء التنفيذ وخلال نافذة الثلاثة أيام: يحق للعميل الإلغاء دون غرامة مع استحقاق M.A.K لما أُنجز فعلاً إن تجاوز ما دُفع. بعد انتهاء النافذة: لا يُسترد العربون، وتُستحق غرامة إلغاء قدرها {{CANCEL_FINE}}% من القيمة الإجمالية تُدفع قبل اعتماد الإلغاء وتُحتسب من العربون أولاً. لا يُعتمد أي إلغاء إلا بعد التحقق من هوية العميل برمز الطلب.

المادة 7 — التسليم والمواعيد
تبدأ المواعيد بعد استلام المواد المطلوبة من العميل والدفعة المتفق عليها. أي تأخر من العميل في الرد أو تقديم المواد يمدّد موعد التسليم بالمدة نفسها. المواعيد تقديرية ما لم يُنص على غير ذلك كتابياً. يتم التسليم داخل التطبيق، ويُعدّ الإشعار الظاهر في الطلب إثباتاً للتسليم.

المادة 8 — الاستلام والقبول
يُعدّ العمل مقبولاً إذا لم يقدّم العميل اعتراضاً مكتوباً ومسبباً داخل التطبيق خلال 5 أيام من التسليم، أو عند أول استخدام تجاري للعمل أيهما أسبق. الاعتراضات اللاحقة تُعامَل كتعديل بموجب المادة 5.

المادة 9 — المسؤولية المحدودة
لا تتجاوز مسؤولية M.A.K في أي حال المبلغ المدفوع فعلاً من العميل بموجب هذا العقد، ولا تشمل الأضرار غير المباشرة أو فوات الربح أو فقدان البيانات. لا تتحمل M.A.K مسؤولية نتائج استخدام العمل خارج النطاق المتفق عليه أو بعد تعديله من طرف آخر.

المادة 10 — السرية وحماية البيانات
يلتزم الطرفان بسرية المعلومات والملفات المتبادلة وعدم إفشائها لأي طرف ثالث. لا تُستخدم بيانات العميل إلا لتنفيذ الطلب. لا يجوز لـ M.A.K عرض أعمال العميل ضمن معرض أعمالها إلا بإذنه الصريح في البريف (السؤال 30) أو كتابياً لاحقاً. يستمر هذا الالتزام بعد انتهاء العقد.

المادة 11 — عدم التنازل ونطاق الاستخدام
لا يحق لأي طرف التنازل عن هذا العقد أو حقوقه للغير دون موافقة الطرف الآخر كتابياً. يستخدم العميل العمل بعد السداد الكامل ضمن النطاق المتفق عليه فقط، ولا يحق له بيعه أو ترخيصه للغير كمنتج قائم بذاته ما لم يُنص على ذلك.

المادة 12 — القوة القاهرة
لا يُعدّ أي طرف مخالفاً لالتزاماته إذا تأخر أو تعذّر عليه التنفيذ بسبب قوة قاهرة موثقة خارجة عن إرادته (كوارث طبيعية، انقطاع عام للاتصالات أو الكهرباء، قرارات سلطات)، ويُمدَّد الموعد بقدر مدة القوة القاهرة. إن زادت على 30 يوماً جاز لأي طرف إنهاء العقد وتسوية ما أُنجز.

المادة 13 — التوقيع الإلكتروني والإثبات
يقرّ الطرفان بأن التوقيع الإلكتروني عبر التطبيق ملزم قانوناً، وأن سجلات النظام (التواريخ، التوقيعات، سجل التدقيق) حجة مقبولة في الإثبات. لا يكون العقد ساري المفعول إلا بتوقيع الطرفين: العميل وممثل M.A.K المفوّض (المدير).

المادة 14 — تعديل العقد
لا يُعدَّل هذا العقد إلا بملحق مكتوب موقّع من الطرفين. أي تعديل أو وعد من موظف لا يعتمده المدير كتابياً داخل التطبيق يكون باطلاً. بعد التوقيع يصبح نص العقد غير قابل للتعديل.

المادة 15 — القانون المختص وتسوية النزاعات
يخضع هذا العقد للقانون المغربي. يسعى الطرفان أولاً إلى تسوية ودية خلال 15 يوماً من إخطار النزاع كتابياً، وإن تعذّرت فتختص محاكم {{COMPANY_CITY}} بالنظر فيه.

حُرّر إلكترونياً بتاريخ {{DATE}} بنسختين عربية وإنجليزية، وعند التعارض يُعتدّ بالنص العربي.$mak$, $mak$Service Agreement No. {{CONTRACT_ID}}
Linked to order {{ORDER_ID}} — dated {{DATE}}

Between:
First party ("M.A.K"): {{COMPANY_NAME}} — City: {{COMPANY_CITY}} — Email: {{COMPANY_EMAIL}}.
Second party (the "Client"): {{CLIENT_NAME}} — Email: {{CLIENT_EMAIL}}.

Article 1 — Definitions and Parties
"Order": the service request recorded in the app under number {{ORDER_ID}}, including the brief and approved options. "Preview": a watermarked working copy not suitable for commercial use. "Final Version": the watermark-free files delivered after full payment. "Addendum": a written document signed by both parties that amends this Agreement. "Execution Start": the moment both parties have signed this Agreement and the start-of-execution notice is sent to the Client inside the app.

Article 2 — Scope of Work
M.A.K shall perform only the service described in the Order and the approved options: {{SCOPE}}. {{SECTION_NOTE}} Any work outside this scope requires a signed Addendum stating the price and timeline. The service includes {{REVISIONS}} revision rounds; additional rounds are treated as paid modifications under Article 5.

Article 3 — Originality and Intellectual Property
M.A.K warrants that the delivered work is its own production or lawfully licensed to it, and that to its knowledge it does not infringe third-party rights. Third-party fonts, images and assets: licensing is M.A.K's responsibility if M.A.K supplied them, and the Client's if the Client supplied them. Usage rights in the Final Version pass to the Client only after full payment; until then all rights remain with M.A.K and only the watermarked Preview may be used. Usage is exclusive or non-exclusive as stated in the Order or Addendum, and M.A.K keeps its moral rights as author.

Article 4 — Fees and Payment
The total contract value is {{TOTAL}}. A deposit of {{DEPOSIT}} is payable upon signing; the balance is payable as agreed before delivery of the Final Version. Payment is made by bank transfer to the company account shown in the app and is complete once M.A.K confirms receipt. The Final Version is not released before full payment unless cash-on-delivery has been agreed in writing.

Article 5 — Three-Day Window and Modifications
The three (3) day window starts at Execution Start; during it the Client may request modifications or cancellation free of charge (subject to Article 6). After it ends, every modification carries a surcharge of at least {{MODIFY_FEE}}% of the contract value; M.A.K sets the final rate (5%–10%) according to the size of the change, approved by a signed Addendum before work begins.

Article 6 — Cancellation
Before Execution Start the deposit is refunded in full. After Execution Start and within the three-day window the Client may cancel without penalty, while M.A.K remains entitled to payment for work actually done if it exceeds what was paid. After the window the deposit is non-refundable and a cancellation fine of {{CANCEL_FINE}}% of the total value is due, payable before the cancellation is approved and deducted from the deposit first. No cancellation is approved without verifying the Client's identity with the order code.

Article 7 — Delivery and Timelines
Timelines start once the required materials and the agreed payment are received. Any Client delay in responding or providing materials extends the delivery date by the same period. Dates are estimates unless stated otherwise in writing. Delivery takes place inside the app and the notice shown in the Order is proof of delivery.

Article 8 — Acceptance
The work is deemed accepted if the Client submits no written, reasoned objection inside the app within 5 days of delivery, or upon first commercial use, whichever is earlier. Later objections are treated as modifications under Article 5.

Article 9 — Limitation of Liability
M.A.K's total liability shall in no case exceed the amount actually paid by the Client under this Agreement and excludes indirect damages, lost profits and data loss. M.A.K is not liable for use of the work outside the agreed scope or after modification by another party.

Article 10 — Confidentiality and Data Protection
Both parties shall keep exchanged information and files confidential and not disclose them to any third party. Client data is used only to perform the Order. M.A.K may not showcase the Client's work in its portfolio except with the Client's explicit permission in the brief (question 30) or later in writing. This obligation survives termination.

Article 11 — No Assignment and Scope of Use
Neither party may assign this Agreement or its rights to others without the other's written consent. After full payment the Client may use the work only within the agreed scope and may not resell or license it to others as a standalone product unless stated otherwise.

Article 12 — Force Majeure
Neither party breaches its obligations by delay or inability to perform caused by documented force majeure beyond its control (natural disasters, general telecom or power outages, government orders), and the deadline is extended by the duration of the event. If it exceeds 30 days either party may terminate and settle the work done.

Article 13 — Electronic Signature and Evidence
The parties acknowledge that electronic signature through the app is legally binding and that system records (dates, signatures, audit log) are admissible evidence. This Agreement is effective only when signed by both the Client and M.A.K's authorized representative (the Admin).

Article 14 — Amendment
This Agreement may be amended only by a written Addendum signed by both parties. Any amendment or promise by an employee not approved in writing by the Admin inside the app is void. Once signed, the text of this Agreement cannot be edited.

Article 15 — Governing Law and Dispute Resolution
This Agreement is governed by Moroccan law. The parties shall first seek an amicable settlement within 15 days of written notice of the dispute; failing that, the courts of {{COMPANY_CITY}} shall have jurisdiction.

Executed electronically on {{DATE}} in Arabic and English; in case of conflict the Arabic text prevails.$mak$),
('web', 'عقد خدمة برمجة M.A.K', $mak$عقد خدمة رقم {{CONTRACT_ID}}
المرتبط بالطلب رقم {{ORDER_ID}} — بتاريخ {{DATE}}

بين الطرفين:
الطرف الأول («M.A.K»): {{COMPANY_NAME}} — المدينة: {{COMPANY_CITY}} — البريد: {{COMPANY_EMAIL}}.
الطرف الثاني («العميل»): {{CLIENT_NAME}} — البريد: {{CLIENT_EMAIL}}.

المادة 1 — التعريفات والأطراف
«الطلب»: طلب الخدمة المسجّل في التطبيق برقم {{ORDER_ID}} بما فيه البريف والخيارات المعتمدة. «المعاينة»: نسخة عمل بعلامة مائية لا تصلح للاستخدام التجاري. «النسخة النهائية»: الملفات الخالية من العلامة المائية التي تُسلَّم بعد السداد الكامل. «ملحق»: وثيقة مكتوبة وموقّعة من الطرفين تعدّل هذا العقد. «بدء التنفيذ»: لحظة توقيع الطرفين على هذا العقد وإرسال إشعار بدء التنفيذ إلى العميل داخل التطبيق.

المادة 2 — نطاق العمل
تلتزم M.A.K بتنفيذ الخدمة الموصوفة في الطلب والخيارات المعتمدة فقط: {{SCOPE}}. {{SECTION_NOTE}} أي عمل خارج هذا النطاق يتطلب ملحقاً موقّعاً يحدد السعر والمدة. تشمل الخدمة عدد جولات مراجعة قدره {{REVISIONS}} جولات؛ وما زاد عنها يُعامَل كتعديل مدفوع وفق المادة 5.

المادة 3 — الأصالة والملكية الفكرية
تضمن M.A.K أن العمل المسلَّم من إنتاجها أو مرخّص لها قانونياً، وأنه لا ينتهك حقوق طرف ثالث بعلمها. الخطوط والصور والعناصر المرخّصة من طرف ثالث: مسؤولية الترخيص على M.A.K إن قدّمتها هي، وعلى العميل إن قدّمها هو. تنتقل حقوق استخدام النسخة النهائية إلى العميل بعد السداد الكامل فقط، وقبل ذلك تبقى الحقوق لـ M.A.K ولا يجوز استخدام غير المعاينة بعلامتها المائية. حق الاستخدام حصري أو غير حصري حسب ما يُنص عليه في الطلب أو الملحق، وتحتفظ M.A.K بحقها المعنوي كمؤلف للعمل.

المادة 4 — المقابل والدفع
القيمة الإجمالية للعقد {{TOTAL}}. عربون {{DEPOSIT}} يُدفع عند توقيع العقد، والباقي حسب الاتفاق قبل تسليم النسخة النهائية. الدفع بالتحويل البنكي إلى الحساب المعلن للشركة داخل التطبيق، ويُعدّ الدفع مكتملاً بتأكيد M.A.K استلام المبلغ. لا تُسلَّم النسخة النهائية قبل اكتمال السداد ما لم يُتفق كتابياً على الدفع عند التسليم.

المادة 5 — نافذة الثلاثة أيام والتعديلات
تبدأ نافذة الثلاثة (3) أيام من بدء التنفيذ؛ خلالها يحق للعميل طلب التعديل أو الإلغاء مجاناً (مع مراعاة المادة 6). بعد انتهائها يخضع كل تعديل لزيادة قدرها {{MODIFY_FEE}}% من قيمة العقد على الأقل، وتحدد M.A.K النسبة النهائية (من 5% إلى 10%) حسب حجم التعديل، وتُعتمد بملحق موقّع قبل البدء به.

المادة 6 — الإلغاء
قبل بدء التنفيذ: يُسترد العربون كاملاً. بعد بدء التنفيذ وخلال نافذة الثلاثة أيام: يحق للعميل الإلغاء دون غرامة مع استحقاق M.A.K لما أُنجز فعلاً إن تجاوز ما دُفع. بعد انتهاء النافذة: لا يُسترد العربون، وتُستحق غرامة إلغاء قدرها {{CANCEL_FINE}}% من القيمة الإجمالية تُدفع قبل اعتماد الإلغاء وتُحتسب من العربون أولاً. لا يُعتمد أي إلغاء إلا بعد التحقق من هوية العميل برمز الطلب.

المادة 7 — التسليم والمواعيد
تبدأ المواعيد بعد استلام المواد المطلوبة من العميل والدفعة المتفق عليها. أي تأخر من العميل في الرد أو تقديم المواد يمدّد موعد التسليم بالمدة نفسها. المواعيد تقديرية ما لم يُنص على غير ذلك كتابياً. يتم التسليم داخل التطبيق، ويُعدّ الإشعار الظاهر في الطلب إثباتاً للتسليم.

المادة 8 — الاستلام والقبول
يُعدّ العمل مقبولاً إذا لم يقدّم العميل اعتراضاً مكتوباً ومسبباً داخل التطبيق خلال 5 أيام من التسليم، أو عند أول استخدام تجاري للعمل أيهما أسبق. الاعتراضات اللاحقة تُعامَل كتعديل بموجب المادة 5.

المادة 9 — المسؤولية المحدودة
لا تتجاوز مسؤولية M.A.K في أي حال المبلغ المدفوع فعلاً من العميل بموجب هذا العقد، ولا تشمل الأضرار غير المباشرة أو فوات الربح أو فقدان البيانات. لا تتحمل M.A.K مسؤولية نتائج استخدام العمل خارج النطاق المتفق عليه أو بعد تعديله من طرف آخر.

المادة 10 — السرية وحماية البيانات
يلتزم الطرفان بسرية المعلومات والملفات المتبادلة وعدم إفشائها لأي طرف ثالث. لا تُستخدم بيانات العميل إلا لتنفيذ الطلب. لا يجوز لـ M.A.K عرض أعمال العميل ضمن معرض أعمالها إلا بإذنه الصريح في البريف (السؤال 30) أو كتابياً لاحقاً. يستمر هذا الالتزام بعد انتهاء العقد.

المادة 11 — عدم التنازل ونطاق الاستخدام
لا يحق لأي طرف التنازل عن هذا العقد أو حقوقه للغير دون موافقة الطرف الآخر كتابياً. يستخدم العميل العمل بعد السداد الكامل ضمن النطاق المتفق عليه فقط، ولا يحق له بيعه أو ترخيصه للغير كمنتج قائم بذاته ما لم يُنص على ذلك.

المادة 12 — القوة القاهرة
لا يُعدّ أي طرف مخالفاً لالتزاماته إذا تأخر أو تعذّر عليه التنفيذ بسبب قوة قاهرة موثقة خارجة عن إرادته (كوارث طبيعية، انقطاع عام للاتصالات أو الكهرباء، قرارات سلطات)، ويُمدَّد الموعد بقدر مدة القوة القاهرة. إن زادت على 30 يوماً جاز لأي طرف إنهاء العقد وتسوية ما أُنجز.

المادة 13 — التوقيع الإلكتروني والإثبات
يقرّ الطرفان بأن التوقيع الإلكتروني عبر التطبيق ملزم قانوناً، وأن سجلات النظام (التواريخ، التوقيعات، سجل التدقيق) حجة مقبولة في الإثبات. لا يكون العقد ساري المفعول إلا بتوقيع الطرفين: العميل وممثل M.A.K المفوّض (المدير).

المادة 14 — تعديل العقد
لا يُعدَّل هذا العقد إلا بملحق مكتوب موقّع من الطرفين. أي تعديل أو وعد من موظف لا يعتمده المدير كتابياً داخل التطبيق يكون باطلاً. بعد التوقيع يصبح نص العقد غير قابل للتعديل.

المادة 15 — القانون المختص وتسوية النزاعات
يخضع هذا العقد للقانون المغربي. يسعى الطرفان أولاً إلى تسوية ودية خلال 15 يوماً من إخطار النزاع كتابياً، وإن تعذّرت فتختص محاكم {{COMPANY_CITY}} بالنظر فيه.

حُرّر إلكترونياً بتاريخ {{DATE}} بنسختين عربية وإنجليزية، وعند التعارض يُعتدّ بالنص العربي.$mak$, $mak$Service Agreement No. {{CONTRACT_ID}}
Linked to order {{ORDER_ID}} — dated {{DATE}}

Between:
First party ("M.A.K"): {{COMPANY_NAME}} — City: {{COMPANY_CITY}} — Email: {{COMPANY_EMAIL}}.
Second party (the "Client"): {{CLIENT_NAME}} — Email: {{CLIENT_EMAIL}}.

Article 1 — Definitions and Parties
"Order": the service request recorded in the app under number {{ORDER_ID}}, including the brief and approved options. "Preview": a watermarked working copy not suitable for commercial use. "Final Version": the watermark-free files delivered after full payment. "Addendum": a written document signed by both parties that amends this Agreement. "Execution Start": the moment both parties have signed this Agreement and the start-of-execution notice is sent to the Client inside the app.

Article 2 — Scope of Work
M.A.K shall perform only the service described in the Order and the approved options: {{SCOPE}}. {{SECTION_NOTE}} Any work outside this scope requires a signed Addendum stating the price and timeline. The service includes {{REVISIONS}} revision rounds; additional rounds are treated as paid modifications under Article 5.

Article 3 — Originality and Intellectual Property
M.A.K warrants that the delivered work is its own production or lawfully licensed to it, and that to its knowledge it does not infringe third-party rights. Third-party fonts, images and assets: licensing is M.A.K's responsibility if M.A.K supplied them, and the Client's if the Client supplied them. Usage rights in the Final Version pass to the Client only after full payment; until then all rights remain with M.A.K and only the watermarked Preview may be used. Usage is exclusive or non-exclusive as stated in the Order or Addendum, and M.A.K keeps its moral rights as author.

Article 4 — Fees and Payment
The total contract value is {{TOTAL}}. A deposit of {{DEPOSIT}} is payable upon signing; the balance is payable as agreed before delivery of the Final Version. Payment is made by bank transfer to the company account shown in the app and is complete once M.A.K confirms receipt. The Final Version is not released before full payment unless cash-on-delivery has been agreed in writing.

Article 5 — Three-Day Window and Modifications
The three (3) day window starts at Execution Start; during it the Client may request modifications or cancellation free of charge (subject to Article 6). After it ends, every modification carries a surcharge of at least {{MODIFY_FEE}}% of the contract value; M.A.K sets the final rate (5%–10%) according to the size of the change, approved by a signed Addendum before work begins.

Article 6 — Cancellation
Before Execution Start the deposit is refunded in full. After Execution Start and within the three-day window the Client may cancel without penalty, while M.A.K remains entitled to payment for work actually done if it exceeds what was paid. After the window the deposit is non-refundable and a cancellation fine of {{CANCEL_FINE}}% of the total value is due, payable before the cancellation is approved and deducted from the deposit first. No cancellation is approved without verifying the Client's identity with the order code.

Article 7 — Delivery and Timelines
Timelines start once the required materials and the agreed payment are received. Any Client delay in responding or providing materials extends the delivery date by the same period. Dates are estimates unless stated otherwise in writing. Delivery takes place inside the app and the notice shown in the Order is proof of delivery.

Article 8 — Acceptance
The work is deemed accepted if the Client submits no written, reasoned objection inside the app within 5 days of delivery, or upon first commercial use, whichever is earlier. Later objections are treated as modifications under Article 5.

Article 9 — Limitation of Liability
M.A.K's total liability shall in no case exceed the amount actually paid by the Client under this Agreement and excludes indirect damages, lost profits and data loss. M.A.K is not liable for use of the work outside the agreed scope or after modification by another party.

Article 10 — Confidentiality and Data Protection
Both parties shall keep exchanged information and files confidential and not disclose them to any third party. Client data is used only to perform the Order. M.A.K may not showcase the Client's work in its portfolio except with the Client's explicit permission in the brief (question 30) or later in writing. This obligation survives termination.

Article 11 — No Assignment and Scope of Use
Neither party may assign this Agreement or its rights to others without the other's written consent. After full payment the Client may use the work only within the agreed scope and may not resell or license it to others as a standalone product unless stated otherwise.

Article 12 — Force Majeure
Neither party breaches its obligations by delay or inability to perform caused by documented force majeure beyond its control (natural disasters, general telecom or power outages, government orders), and the deadline is extended by the duration of the event. If it exceeds 30 days either party may terminate and settle the work done.

Article 13 — Electronic Signature and Evidence
The parties acknowledge that electronic signature through the app is legally binding and that system records (dates, signatures, audit log) are admissible evidence. This Agreement is effective only when signed by both the Client and M.A.K's authorized representative (the Admin).

Article 14 — Amendment
This Agreement may be amended only by a written Addendum signed by both parties. Any amendment or promise by an employee not approved in writing by the Admin inside the app is void. Once signed, the text of this Agreement cannot be edited.

Article 15 — Governing Law and Dispute Resolution
This Agreement is governed by Moroccan law. The parties shall first seek an amicable settlement within 15 days of written notice of the dispute; failing that, the courts of {{COMPANY_CITY}} shall have jurisdiction.

Executed electronically on {{DATE}} in Arabic and English; in case of conflict the Arabic text prevails.$mak$),
('writing', 'عقد خدمة كتابة M.A.K', $mak$عقد خدمة رقم {{CONTRACT_ID}}
المرتبط بالطلب رقم {{ORDER_ID}} — بتاريخ {{DATE}}

بين الطرفين:
الطرف الأول («M.A.K»): {{COMPANY_NAME}} — المدينة: {{COMPANY_CITY}} — البريد: {{COMPANY_EMAIL}}.
الطرف الثاني («العميل»): {{CLIENT_NAME}} — البريد: {{CLIENT_EMAIL}}.

المادة 1 — التعريفات والأطراف
«الطلب»: طلب الخدمة المسجّل في التطبيق برقم {{ORDER_ID}} بما فيه البريف والخيارات المعتمدة. «المعاينة»: نسخة عمل بعلامة مائية لا تصلح للاستخدام التجاري. «النسخة النهائية»: الملفات الخالية من العلامة المائية التي تُسلَّم بعد السداد الكامل. «ملحق»: وثيقة مكتوبة وموقّعة من الطرفين تعدّل هذا العقد. «بدء التنفيذ»: لحظة توقيع الطرفين على هذا العقد وإرسال إشعار بدء التنفيذ إلى العميل داخل التطبيق.

المادة 2 — نطاق العمل
تلتزم M.A.K بتنفيذ الخدمة الموصوفة في الطلب والخيارات المعتمدة فقط: {{SCOPE}}. {{SECTION_NOTE}} أي عمل خارج هذا النطاق يتطلب ملحقاً موقّعاً يحدد السعر والمدة. تشمل الخدمة عدد جولات مراجعة قدره {{REVISIONS}} جولات؛ وما زاد عنها يُعامَل كتعديل مدفوع وفق المادة 5.

المادة 3 — الأصالة والملكية الفكرية
تضمن M.A.K أن العمل المسلَّم من إنتاجها أو مرخّص لها قانونياً، وأنه لا ينتهك حقوق طرف ثالث بعلمها. الخطوط والصور والعناصر المرخّصة من طرف ثالث: مسؤولية الترخيص على M.A.K إن قدّمتها هي، وعلى العميل إن قدّمها هو. تنتقل حقوق استخدام النسخة النهائية إلى العميل بعد السداد الكامل فقط، وقبل ذلك تبقى الحقوق لـ M.A.K ولا يجوز استخدام غير المعاينة بعلامتها المائية. حق الاستخدام حصري أو غير حصري حسب ما يُنص عليه في الطلب أو الملحق، وتحتفظ M.A.K بحقها المعنوي كمؤلف للعمل.

المادة 4 — المقابل والدفع
القيمة الإجمالية للعقد {{TOTAL}}. عربون {{DEPOSIT}} يُدفع عند توقيع العقد، والباقي حسب الاتفاق قبل تسليم النسخة النهائية. الدفع بالتحويل البنكي إلى الحساب المعلن للشركة داخل التطبيق، ويُعدّ الدفع مكتملاً بتأكيد M.A.K استلام المبلغ. لا تُسلَّم النسخة النهائية قبل اكتمال السداد ما لم يُتفق كتابياً على الدفع عند التسليم.

المادة 5 — نافذة الثلاثة أيام والتعديلات
تبدأ نافذة الثلاثة (3) أيام من بدء التنفيذ؛ خلالها يحق للعميل طلب التعديل أو الإلغاء مجاناً (مع مراعاة المادة 6). بعد انتهائها يخضع كل تعديل لزيادة قدرها {{MODIFY_FEE}}% من قيمة العقد على الأقل، وتحدد M.A.K النسبة النهائية (من 5% إلى 10%) حسب حجم التعديل، وتُعتمد بملحق موقّع قبل البدء به.

المادة 6 — الإلغاء
قبل بدء التنفيذ: يُسترد العربون كاملاً. بعد بدء التنفيذ وخلال نافذة الثلاثة أيام: يحق للعميل الإلغاء دون غرامة مع استحقاق M.A.K لما أُنجز فعلاً إن تجاوز ما دُفع. بعد انتهاء النافذة: لا يُسترد العربون، وتُستحق غرامة إلغاء قدرها {{CANCEL_FINE}}% من القيمة الإجمالية تُدفع قبل اعتماد الإلغاء وتُحتسب من العربون أولاً. لا يُعتمد أي إلغاء إلا بعد التحقق من هوية العميل برمز الطلب.

المادة 7 — التسليم والمواعيد
تبدأ المواعيد بعد استلام المواد المطلوبة من العميل والدفعة المتفق عليها. أي تأخر من العميل في الرد أو تقديم المواد يمدّد موعد التسليم بالمدة نفسها. المواعيد تقديرية ما لم يُنص على غير ذلك كتابياً. يتم التسليم داخل التطبيق، ويُعدّ الإشعار الظاهر في الطلب إثباتاً للتسليم.

المادة 8 — الاستلام والقبول
يُعدّ العمل مقبولاً إذا لم يقدّم العميل اعتراضاً مكتوباً ومسبباً داخل التطبيق خلال 5 أيام من التسليم، أو عند أول استخدام تجاري للعمل أيهما أسبق. الاعتراضات اللاحقة تُعامَل كتعديل بموجب المادة 5.

المادة 9 — المسؤولية المحدودة
لا تتجاوز مسؤولية M.A.K في أي حال المبلغ المدفوع فعلاً من العميل بموجب هذا العقد، ولا تشمل الأضرار غير المباشرة أو فوات الربح أو فقدان البيانات. لا تتحمل M.A.K مسؤولية نتائج استخدام العمل خارج النطاق المتفق عليه أو بعد تعديله من طرف آخر.

المادة 10 — السرية وحماية البيانات
يلتزم الطرفان بسرية المعلومات والملفات المتبادلة وعدم إفشائها لأي طرف ثالث. لا تُستخدم بيانات العميل إلا لتنفيذ الطلب. لا يجوز لـ M.A.K عرض أعمال العميل ضمن معرض أعمالها إلا بإذنه الصريح في البريف (السؤال 30) أو كتابياً لاحقاً. يستمر هذا الالتزام بعد انتهاء العقد.

المادة 11 — عدم التنازل ونطاق الاستخدام
لا يحق لأي طرف التنازل عن هذا العقد أو حقوقه للغير دون موافقة الطرف الآخر كتابياً. يستخدم العميل العمل بعد السداد الكامل ضمن النطاق المتفق عليه فقط، ولا يحق له بيعه أو ترخيصه للغير كمنتج قائم بذاته ما لم يُنص على ذلك.

المادة 12 — القوة القاهرة
لا يُعدّ أي طرف مخالفاً لالتزاماته إذا تأخر أو تعذّر عليه التنفيذ بسبب قوة قاهرة موثقة خارجة عن إرادته (كوارث طبيعية، انقطاع عام للاتصالات أو الكهرباء، قرارات سلطات)، ويُمدَّد الموعد بقدر مدة القوة القاهرة. إن زادت على 30 يوماً جاز لأي طرف إنهاء العقد وتسوية ما أُنجز.

المادة 13 — التوقيع الإلكتروني والإثبات
يقرّ الطرفان بأن التوقيع الإلكتروني عبر التطبيق ملزم قانوناً، وأن سجلات النظام (التواريخ، التوقيعات، سجل التدقيق) حجة مقبولة في الإثبات. لا يكون العقد ساري المفعول إلا بتوقيع الطرفين: العميل وممثل M.A.K المفوّض (المدير).

المادة 14 — تعديل العقد
لا يُعدَّل هذا العقد إلا بملحق مكتوب موقّع من الطرفين. أي تعديل أو وعد من موظف لا يعتمده المدير كتابياً داخل التطبيق يكون باطلاً. بعد التوقيع يصبح نص العقد غير قابل للتعديل.

المادة 15 — القانون المختص وتسوية النزاعات
يخضع هذا العقد للقانون المغربي. يسعى الطرفان أولاً إلى تسوية ودية خلال 15 يوماً من إخطار النزاع كتابياً، وإن تعذّرت فتختص محاكم {{COMPANY_CITY}} بالنظر فيه.

حُرّر إلكترونياً بتاريخ {{DATE}} بنسختين عربية وإنجليزية، وعند التعارض يُعتدّ بالنص العربي.$mak$, $mak$Service Agreement No. {{CONTRACT_ID}}
Linked to order {{ORDER_ID}} — dated {{DATE}}

Between:
First party ("M.A.K"): {{COMPANY_NAME}} — City: {{COMPANY_CITY}} — Email: {{COMPANY_EMAIL}}.
Second party (the "Client"): {{CLIENT_NAME}} — Email: {{CLIENT_EMAIL}}.

Article 1 — Definitions and Parties
"Order": the service request recorded in the app under number {{ORDER_ID}}, including the brief and approved options. "Preview": a watermarked working copy not suitable for commercial use. "Final Version": the watermark-free files delivered after full payment. "Addendum": a written document signed by both parties that amends this Agreement. "Execution Start": the moment both parties have signed this Agreement and the start-of-execution notice is sent to the Client inside the app.

Article 2 — Scope of Work
M.A.K shall perform only the service described in the Order and the approved options: {{SCOPE}}. {{SECTION_NOTE}} Any work outside this scope requires a signed Addendum stating the price and timeline. The service includes {{REVISIONS}} revision rounds; additional rounds are treated as paid modifications under Article 5.

Article 3 — Originality and Intellectual Property
M.A.K warrants that the delivered work is its own production or lawfully licensed to it, and that to its knowledge it does not infringe third-party rights. Third-party fonts, images and assets: licensing is M.A.K's responsibility if M.A.K supplied them, and the Client's if the Client supplied them. Usage rights in the Final Version pass to the Client only after full payment; until then all rights remain with M.A.K and only the watermarked Preview may be used. Usage is exclusive or non-exclusive as stated in the Order or Addendum, and M.A.K keeps its moral rights as author.

Article 4 — Fees and Payment
The total contract value is {{TOTAL}}. A deposit of {{DEPOSIT}} is payable upon signing; the balance is payable as agreed before delivery of the Final Version. Payment is made by bank transfer to the company account shown in the app and is complete once M.A.K confirms receipt. The Final Version is not released before full payment unless cash-on-delivery has been agreed in writing.

Article 5 — Three-Day Window and Modifications
The three (3) day window starts at Execution Start; during it the Client may request modifications or cancellation free of charge (subject to Article 6). After it ends, every modification carries a surcharge of at least {{MODIFY_FEE}}% of the contract value; M.A.K sets the final rate (5%–10%) according to the size of the change, approved by a signed Addendum before work begins.

Article 6 — Cancellation
Before Execution Start the deposit is refunded in full. After Execution Start and within the three-day window the Client may cancel without penalty, while M.A.K remains entitled to payment for work actually done if it exceeds what was paid. After the window the deposit is non-refundable and a cancellation fine of {{CANCEL_FINE}}% of the total value is due, payable before the cancellation is approved and deducted from the deposit first. No cancellation is approved without verifying the Client's identity with the order code.

Article 7 — Delivery and Timelines
Timelines start once the required materials and the agreed payment are received. Any Client delay in responding or providing materials extends the delivery date by the same period. Dates are estimates unless stated otherwise in writing. Delivery takes place inside the app and the notice shown in the Order is proof of delivery.

Article 8 — Acceptance
The work is deemed accepted if the Client submits no written, reasoned objection inside the app within 5 days of delivery, or upon first commercial use, whichever is earlier. Later objections are treated as modifications under Article 5.

Article 9 — Limitation of Liability
M.A.K's total liability shall in no case exceed the amount actually paid by the Client under this Agreement and excludes indirect damages, lost profits and data loss. M.A.K is not liable for use of the work outside the agreed scope or after modification by another party.

Article 10 — Confidentiality and Data Protection
Both parties shall keep exchanged information and files confidential and not disclose them to any third party. Client data is used only to perform the Order. M.A.K may not showcase the Client's work in its portfolio except with the Client's explicit permission in the brief (question 30) or later in writing. This obligation survives termination.

Article 11 — No Assignment and Scope of Use
Neither party may assign this Agreement or its rights to others without the other's written consent. After full payment the Client may use the work only within the agreed scope and may not resell or license it to others as a standalone product unless stated otherwise.

Article 12 — Force Majeure
Neither party breaches its obligations by delay or inability to perform caused by documented force majeure beyond its control (natural disasters, general telecom or power outages, government orders), and the deadline is extended by the duration of the event. If it exceeds 30 days either party may terminate and settle the work done.

Article 13 — Electronic Signature and Evidence
The parties acknowledge that electronic signature through the app is legally binding and that system records (dates, signatures, audit log) are admissible evidence. This Agreement is effective only when signed by both the Client and M.A.K's authorized representative (the Admin).

Article 14 — Amendment
This Agreement may be amended only by a written Addendum signed by both parties. Any amendment or promise by an employee not approved in writing by the Admin inside the app is void. Once signed, the text of this Agreement cannot be edited.

Article 15 — Governing Law and Dispute Resolution
This Agreement is governed by Moroccan law. The parties shall first seek an amicable settlement within 15 days of written notice of the dispute; failing that, the courts of {{COMPANY_CITY}} shall have jurisdiction.

Executed electronically on {{DATE}} in Arabic and English; in case of conflict the Arabic text prevails.$mak$),
('general', 'عقد M.A.K الشامل', $mak$عقد خدمة رقم {{CONTRACT_ID}}
المرتبط بالطلب رقم {{ORDER_ID}} — بتاريخ {{DATE}}

بين الطرفين:
الطرف الأول («M.A.K»): {{COMPANY_NAME}} — المدينة: {{COMPANY_CITY}} — البريد: {{COMPANY_EMAIL}}.
الطرف الثاني («العميل»): {{CLIENT_NAME}} — البريد: {{CLIENT_EMAIL}}.

المادة 1 — التعريفات والأطراف
«الطلب»: طلب الخدمة المسجّل في التطبيق برقم {{ORDER_ID}} بما فيه البريف والخيارات المعتمدة. «المعاينة»: نسخة عمل بعلامة مائية لا تصلح للاستخدام التجاري. «النسخة النهائية»: الملفات الخالية من العلامة المائية التي تُسلَّم بعد السداد الكامل. «ملحق»: وثيقة مكتوبة وموقّعة من الطرفين تعدّل هذا العقد. «بدء التنفيذ»: لحظة توقيع الطرفين على هذا العقد وإرسال إشعار بدء التنفيذ إلى العميل داخل التطبيق.

المادة 2 — نطاق العمل
تلتزم M.A.K بتنفيذ الخدمة الموصوفة في الطلب والخيارات المعتمدة فقط: {{SCOPE}}. {{SECTION_NOTE}} أي عمل خارج هذا النطاق يتطلب ملحقاً موقّعاً يحدد السعر والمدة. تشمل الخدمة عدد جولات مراجعة قدره {{REVISIONS}} جولات؛ وما زاد عنها يُعامَل كتعديل مدفوع وفق المادة 5.

المادة 3 — الأصالة والملكية الفكرية
تضمن M.A.K أن العمل المسلَّم من إنتاجها أو مرخّص لها قانونياً، وأنه لا ينتهك حقوق طرف ثالث بعلمها. الخطوط والصور والعناصر المرخّصة من طرف ثالث: مسؤولية الترخيص على M.A.K إن قدّمتها هي، وعلى العميل إن قدّمها هو. تنتقل حقوق استخدام النسخة النهائية إلى العميل بعد السداد الكامل فقط، وقبل ذلك تبقى الحقوق لـ M.A.K ولا يجوز استخدام غير المعاينة بعلامتها المائية. حق الاستخدام حصري أو غير حصري حسب ما يُنص عليه في الطلب أو الملحق، وتحتفظ M.A.K بحقها المعنوي كمؤلف للعمل.

المادة 4 — المقابل والدفع
القيمة الإجمالية للعقد {{TOTAL}}. عربون {{DEPOSIT}} يُدفع عند توقيع العقد، والباقي حسب الاتفاق قبل تسليم النسخة النهائية. الدفع بالتحويل البنكي إلى الحساب المعلن للشركة داخل التطبيق، ويُعدّ الدفع مكتملاً بتأكيد M.A.K استلام المبلغ. لا تُسلَّم النسخة النهائية قبل اكتمال السداد ما لم يُتفق كتابياً على الدفع عند التسليم.

المادة 5 — نافذة الثلاثة أيام والتعديلات
تبدأ نافذة الثلاثة (3) أيام من بدء التنفيذ؛ خلالها يحق للعميل طلب التعديل أو الإلغاء مجاناً (مع مراعاة المادة 6). بعد انتهائها يخضع كل تعديل لزيادة قدرها {{MODIFY_FEE}}% من قيمة العقد على الأقل، وتحدد M.A.K النسبة النهائية (من 5% إلى 10%) حسب حجم التعديل، وتُعتمد بملحق موقّع قبل البدء به.

المادة 6 — الإلغاء
قبل بدء التنفيذ: يُسترد العربون كاملاً. بعد بدء التنفيذ وخلال نافذة الثلاثة أيام: يحق للعميل الإلغاء دون غرامة مع استحقاق M.A.K لما أُنجز فعلاً إن تجاوز ما دُفع. بعد انتهاء النافذة: لا يُسترد العربون، وتُستحق غرامة إلغاء قدرها {{CANCEL_FINE}}% من القيمة الإجمالية تُدفع قبل اعتماد الإلغاء وتُحتسب من العربون أولاً. لا يُعتمد أي إلغاء إلا بعد التحقق من هوية العميل برمز الطلب.

المادة 7 — التسليم والمواعيد
تبدأ المواعيد بعد استلام المواد المطلوبة من العميل والدفعة المتفق عليها. أي تأخر من العميل في الرد أو تقديم المواد يمدّد موعد التسليم بالمدة نفسها. المواعيد تقديرية ما لم يُنص على غير ذلك كتابياً. يتم التسليم داخل التطبيق، ويُعدّ الإشعار الظاهر في الطلب إثباتاً للتسليم.

المادة 8 — الاستلام والقبول
يُعدّ العمل مقبولاً إذا لم يقدّم العميل اعتراضاً مكتوباً ومسبباً داخل التطبيق خلال 5 أيام من التسليم، أو عند أول استخدام تجاري للعمل أيهما أسبق. الاعتراضات اللاحقة تُعامَل كتعديل بموجب المادة 5.

المادة 9 — المسؤولية المحدودة
لا تتجاوز مسؤولية M.A.K في أي حال المبلغ المدفوع فعلاً من العميل بموجب هذا العقد، ولا تشمل الأضرار غير المباشرة أو فوات الربح أو فقدان البيانات. لا تتحمل M.A.K مسؤولية نتائج استخدام العمل خارج النطاق المتفق عليه أو بعد تعديله من طرف آخر.

المادة 10 — السرية وحماية البيانات
يلتزم الطرفان بسرية المعلومات والملفات المتبادلة وعدم إفشائها لأي طرف ثالث. لا تُستخدم بيانات العميل إلا لتنفيذ الطلب. لا يجوز لـ M.A.K عرض أعمال العميل ضمن معرض أعمالها إلا بإذنه الصريح في البريف (السؤال 30) أو كتابياً لاحقاً. يستمر هذا الالتزام بعد انتهاء العقد.

المادة 11 — عدم التنازل ونطاق الاستخدام
لا يحق لأي طرف التنازل عن هذا العقد أو حقوقه للغير دون موافقة الطرف الآخر كتابياً. يستخدم العميل العمل بعد السداد الكامل ضمن النطاق المتفق عليه فقط، ولا يحق له بيعه أو ترخيصه للغير كمنتج قائم بذاته ما لم يُنص على ذلك.

المادة 12 — القوة القاهرة
لا يُعدّ أي طرف مخالفاً لالتزاماته إذا تأخر أو تعذّر عليه التنفيذ بسبب قوة قاهرة موثقة خارجة عن إرادته (كوارث طبيعية، انقطاع عام للاتصالات أو الكهرباء، قرارات سلطات)، ويُمدَّد الموعد بقدر مدة القوة القاهرة. إن زادت على 30 يوماً جاز لأي طرف إنهاء العقد وتسوية ما أُنجز.

المادة 13 — التوقيع الإلكتروني والإثبات
يقرّ الطرفان بأن التوقيع الإلكتروني عبر التطبيق ملزم قانوناً، وأن سجلات النظام (التواريخ، التوقيعات، سجل التدقيق) حجة مقبولة في الإثبات. لا يكون العقد ساري المفعول إلا بتوقيع الطرفين: العميل وممثل M.A.K المفوّض (المدير).

المادة 14 — تعديل العقد
لا يُعدَّل هذا العقد إلا بملحق مكتوب موقّع من الطرفين. أي تعديل أو وعد من موظف لا يعتمده المدير كتابياً داخل التطبيق يكون باطلاً. بعد التوقيع يصبح نص العقد غير قابل للتعديل.

المادة 15 — القانون المختص وتسوية النزاعات
يخضع هذا العقد للقانون المغربي. يسعى الطرفان أولاً إلى تسوية ودية خلال 15 يوماً من إخطار النزاع كتابياً، وإن تعذّرت فتختص محاكم {{COMPANY_CITY}} بالنظر فيه.

حُرّر إلكترونياً بتاريخ {{DATE}} بنسختين عربية وإنجليزية، وعند التعارض يُعتدّ بالنص العربي.$mak$, $mak$Service Agreement No. {{CONTRACT_ID}}
Linked to order {{ORDER_ID}} — dated {{DATE}}

Between:
First party ("M.A.K"): {{COMPANY_NAME}} — City: {{COMPANY_CITY}} — Email: {{COMPANY_EMAIL}}.
Second party (the "Client"): {{CLIENT_NAME}} — Email: {{CLIENT_EMAIL}}.

Article 1 — Definitions and Parties
"Order": the service request recorded in the app under number {{ORDER_ID}}, including the brief and approved options. "Preview": a watermarked working copy not suitable for commercial use. "Final Version": the watermark-free files delivered after full payment. "Addendum": a written document signed by both parties that amends this Agreement. "Execution Start": the moment both parties have signed this Agreement and the start-of-execution notice is sent to the Client inside the app.

Article 2 — Scope of Work
M.A.K shall perform only the service described in the Order and the approved options: {{SCOPE}}. {{SECTION_NOTE}} Any work outside this scope requires a signed Addendum stating the price and timeline. The service includes {{REVISIONS}} revision rounds; additional rounds are treated as paid modifications under Article 5.

Article 3 — Originality and Intellectual Property
M.A.K warrants that the delivered work is its own production or lawfully licensed to it, and that to its knowledge it does not infringe third-party rights. Third-party fonts, images and assets: licensing is M.A.K's responsibility if M.A.K supplied them, and the Client's if the Client supplied them. Usage rights in the Final Version pass to the Client only after full payment; until then all rights remain with M.A.K and only the watermarked Preview may be used. Usage is exclusive or non-exclusive as stated in the Order or Addendum, and M.A.K keeps its moral rights as author.

Article 4 — Fees and Payment
The total contract value is {{TOTAL}}. A deposit of {{DEPOSIT}} is payable upon signing; the balance is payable as agreed before delivery of the Final Version. Payment is made by bank transfer to the company account shown in the app and is complete once M.A.K confirms receipt. The Final Version is not released before full payment unless cash-on-delivery has been agreed in writing.

Article 5 — Three-Day Window and Modifications
The three (3) day window starts at Execution Start; during it the Client may request modifications or cancellation free of charge (subject to Article 6). After it ends, every modification carries a surcharge of at least {{MODIFY_FEE}}% of the contract value; M.A.K sets the final rate (5%–10%) according to the size of the change, approved by a signed Addendum before work begins.

Article 6 — Cancellation
Before Execution Start the deposit is refunded in full. After Execution Start and within the three-day window the Client may cancel without penalty, while M.A.K remains entitled to payment for work actually done if it exceeds what was paid. After the window the deposit is non-refundable and a cancellation fine of {{CANCEL_FINE}}% of the total value is due, payable before the cancellation is approved and deducted from the deposit first. No cancellation is approved without verifying the Client's identity with the order code.

Article 7 — Delivery and Timelines
Timelines start once the required materials and the agreed payment are received. Any Client delay in responding or providing materials extends the delivery date by the same period. Dates are estimates unless stated otherwise in writing. Delivery takes place inside the app and the notice shown in the Order is proof of delivery.

Article 8 — Acceptance
The work is deemed accepted if the Client submits no written, reasoned objection inside the app within 5 days of delivery, or upon first commercial use, whichever is earlier. Later objections are treated as modifications under Article 5.

Article 9 — Limitation of Liability
M.A.K's total liability shall in no case exceed the amount actually paid by the Client under this Agreement and excludes indirect damages, lost profits and data loss. M.A.K is not liable for use of the work outside the agreed scope or after modification by another party.

Article 10 — Confidentiality and Data Protection
Both parties shall keep exchanged information and files confidential and not disclose them to any third party. Client data is used only to perform the Order. M.A.K may not showcase the Client's work in its portfolio except with the Client's explicit permission in the brief (question 30) or later in writing. This obligation survives termination.

Article 11 — No Assignment and Scope of Use
Neither party may assign this Agreement or its rights to others without the other's written consent. After full payment the Client may use the work only within the agreed scope and may not resell or license it to others as a standalone product unless stated otherwise.

Article 12 — Force Majeure
Neither party breaches its obligations by delay or inability to perform caused by documented force majeure beyond its control (natural disasters, general telecom or power outages, government orders), and the deadline is extended by the duration of the event. If it exceeds 30 days either party may terminate and settle the work done.

Article 13 — Electronic Signature and Evidence
The parties acknowledge that electronic signature through the app is legally binding and that system records (dates, signatures, audit log) are admissible evidence. This Agreement is effective only when signed by both the Client and M.A.K's authorized representative (the Admin).

Article 14 — Amendment
This Agreement may be amended only by a written Addendum signed by both parties. Any amendment or promise by an employee not approved in writing by the Admin inside the app is void. Once signed, the text of this Agreement cannot be edited.

Article 15 — Governing Law and Dispute Resolution
This Agreement is governed by Moroccan law. The parties shall first seek an amicable settlement within 15 days of written notice of the dispute; failing that, the courts of {{COMPANY_CITY}} shall have jurisdiction.

Executed electronically on {{DATE}} in Arabic and English; in case of conflict the Arabic text prevails.$mak$)
on conflict (section, title) do update
set body_ar = excluded.body_ar, body_en = excluded.body_en;

-- ------------------------------------------------------------
-- 13) أسئلة البريف الثلاثون (قابلة للتحرير من لوحة المدير)
-- ------------------------------------------------------------
insert into public.brief_questions (key, grp, label_ar, label_en, type, options, active, sort)
values
('q01', 'brand', 'اسم العلامة / المشروع', 'Brand / project name', 'text', '[]'::jsonb, true, 1),
('q02', 'brand', 'مجال النشاط', 'Industry', 'text', '[]'::jsonb, true, 2),
('q03', 'brand', 'شخصية العلامة بجملة واحدة', 'Brand personality in one sentence', 'text', '[]'::jsonb, true, 3),
('q04', 'brand', 'هل لديك شعار / هوية قائمة؟', 'Do you have an existing logo / identity?', 'choice', '["نعم — سأرفعها", "لا — أحتاج واحدة", "تحديث الموجودة"]'::jsonb, true, 4),
('q05', 'brand', 'ألوان العلامة الحالية', 'Current brand colors', 'text', '[]'::jsonb, true, 5),
('q06', 'brand', 'الخط المفضّل', 'Preferred font', 'text', '[]'::jsonb, true, 6),
('q07', 'purpose', 'الغرض من التصميم', 'Purpose', 'choice', '["تسويق", "طباعة", "هوية", "تغليف", "مناسبة"]'::jsonb, true, 7),
('q08', 'purpose', 'أين سيُستخدم؟', 'Where will it be used?', 'text', '[]'::jsonb, true, 8),
('q09', 'purpose', 'عدد النسخ / المتغيرات المطلوبة', 'Number of versions', 'text', '[]'::jsonb, true, 9),
('q10', 'purpose', 'موعد التسليم النهائي المطلوب', 'Final delivery date', 'date', '[]'::jsonb, true, 10),
('q11', 'audience', 'العمر والجنس المستهدف', 'Target age and gender', 'text', '[]'::jsonb, true, 11),
('q12', 'audience', 'اهتمامات الجمهور وسلوكه', 'Audience interests and behavior', 'longtext', '[]'::jsonb, true, 12),
('q13', 'audience', 'المنطقة واللغة', 'Region and language', 'text', '[]'::jsonb, true, 13),
('q14', 'content', 'الرسالة الأساسية', 'Core message', 'longtext', '[]'::jsonb, true, 14),
('q15', 'content', 'النصوص الحرفية الواجب كتابتها', 'Exact texts to include', 'longtext', '[]'::jsonb, true, 15),
('q16', 'content', 'نبرة الكلام', 'Tone of voice', 'text', '[]'::jsonb, true, 16),
('q17', 'content', 'هل يلزم شعار لفظي (Tagline)؟', 'Is a tagline needed?', 'choice', '["نعم", "لا"]'::jsonb, true, 17),
('q18', 'visual', 'مراجع معجب بها ولماذا', 'References you like and why', 'longtext', '[]'::jsonb, true, 18),
('q19', 'visual', 'ما يجب تجنبه', 'What to avoid', 'longtext', '[]'::jsonb, true, 19),
('q20', 'visual', 'ألوان محرّمة', 'Forbidden colors', 'text', '[]'::jsonb, true, 20),
('q21', 'visual', 'Minimalist أم مفصّل؟', 'Minimalist or detailed?', 'choice', '["Minimalist", "مفصّل", "لا فرق"]'::jsonb, true, 21),
('q22', 'visual', 'الأسلوب العام', 'Overall style', 'text', '[]'::jsonb, true, 22),
('q23', 'visual', 'عناصر بصرية مفضلة', 'Preferred visual elements', 'text', '[]'::jsonb, true, 23),
('q24', 'tech', 'الصيغ النهائية المطلوبة', 'Final file formats', 'multi', '["PNG", "JPG", "PDF", "SVG", "PSD", "AI"]'::jsonb, true, 24),
('q25', 'tech', 'المقاسات المطلوبة', 'Required sizes', 'text', '[]'::jsonb, true, 25),
('q26', 'tech', 'هل المخرجات للطباعة (CMYK / 300dpi)؟', 'Print output (CMYK / 300dpi)?', 'choice', '["نعم", "لا"]'::jsonb, true, 26),
('q27', 'tech', 'ملفات المصدر المطلوبة', 'Source files needed', 'multi', '["PSD", "AI", "Figma", "لا أحتاج"]'::jsonb, true, 27),
('q28', 'tech', 'ملاحظات حول الصور والعناصر المرفوعة', 'Notes about uploaded images/assets', 'text', '[]'::jsonb, true, 28),
('q29', 'process', 'من يعتمد التصميم نهائياً وكم عدد المراجعين؟', 'Final approver and number of reviewers', 'text', '[]'::jsonb, true, 29),
('q30', 'process', 'معلومات إضافية (وهل يُسمح بعرض العمل ضمن أعمال M.A.K؟)', 'Extra info (may M.A.K showcase the work?)', 'longtext', '[]'::jsonb, true, 30)
on conflict (key) do nothing;

-- ============================================================
-- END OF ADDITIONS V2
-- ============================================================
