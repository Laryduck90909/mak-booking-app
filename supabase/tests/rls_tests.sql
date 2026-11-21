-- ============================================================
-- اختبارات سريعة للصلاحيات (RLS) — شغّلها في Supabase > SQL Editor
-- بعد تشغيل schema_v3_fixed.sql ثم schema_v2_additions.sql.
-- كل شيء داخل معاملة تُلغى في النهاية (rollback) فلا يبقى أي أثر.
-- النتيجة المتوقعة: رسالة NOTICE "ALL TESTS PASSED" بلا أخطاء.
-- ============================================================
begin;

do $$
declare
    admin_id  uuid := gen_random_uuid();
    client_a  uuid := gen_random_uuid();
    client_b  uuid := gen_random_uuid();
    staff_id  uuid := gen_random_uuid();
    seen int;
    role_after text;
    order_a text;
begin
    -- أول مستخدم في جدول فارغ يصبح مديراً؛ إن كان الجدول غير فارغ نتجاوز هذا الاختبار
    if (select count(*) from public.profiles) = 0 then
        insert into auth.users (id, email, raw_user_meta_data, aud, role)
        values (admin_id, 'admin_test@example.com', '{"full_name":"Admin"}', 'authenticated', 'authenticated');
        assert (select role from public.profiles where id = admin_id) = 'admin', 'FAIL: first user must be admin';
    else
        insert into auth.users (id, email, raw_user_meta_data, aud, role)
        values (admin_id, 'admin_test@example.com', '{"full_name":"Admin"}', 'authenticated', 'authenticated');
        update public.profiles set role = 'admin' where id = admin_id;
    end if;

    -- المستخدمون الجدد = عملاء (هذا كان خطأ النسخة 1.5)
    insert into auth.users (id, email, raw_user_meta_data, aud, role)
    values (client_a, 'client_a_test@example.com', '{"full_name":"Client A"}', 'authenticated', 'authenticated'),
           (client_b, 'client_b_test@example.com', '{"full_name":"Client B"}', 'authenticated', 'authenticated'),
           (staff_id, 'staff_test@example.com',    '{"full_name":"Staff"}',    'authenticated', 'authenticated');
    assert (select role from public.profiles where id = client_a) = 'client', 'FAIL: new user must be client';
    assert (select role from public.profiles where id = client_b) = 'client', 'FAIL: new user must be client';
    update public.profiles set role = 'staff' where id = staff_id;

    -- العميل A ينشئ طلباً
    perform set_config('request.jwt.claims', json_build_object('sub', client_a, 'role', 'authenticated')::text, true);
    set local role authenticated;
    insert into public.orders (client_id, section, title, payload)
    values (client_a, 'design', 'اختبار', '{"brief_answers":{"q01":"Test"}}')
    returning id into order_a;
    select count(*) into seen from public.orders where id = order_a;
    assert seen = 1, 'FAIL: client must see own order';

    -- العميل لا يستطيع ترقية نفسه
    begin
        update public.profiles set role = 'admin' where id = client_a;
    exception when others then null;
    end;
    select role into role_after from public.profiles where id = client_a;
    assert role_after = 'client', 'FAIL: client must not self-promote';
    reset role;

    -- العميل B لا يرى طلب A
    perform set_config('request.jwt.claims', json_build_object('sub', client_b, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into seen from public.orders where id = order_a;
    assert seen = 0, 'FAIL: client B must NOT see client A order';
    reset role;

    -- الموظف يرى الطلب بكامل محتواه (مشكلة: "لا يظهر للمصمم أي شيء")
    perform set_config('request.jwt.claims', json_build_object('sub', staff_id, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into seen from public.orders where id = order_a and payload ? 'brief_answers';
    assert seen = 1, 'FAIL: staff must see order payload (brief answers)';
    reset role;

    raise notice 'ALL TESTS PASSED';
end $$;

rollback;
