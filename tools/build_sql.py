#!/usr/bin/env python3
"""يبني supabase/schema_v2_additions.sql من نصوص العقد وأسئلة البريف في assets/data.
شغّله بعد أي تعديل على contract_ar.txt / contract_en.txt / brief_questions.json:
    python3 tools/build_sql.py
"""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ar = open(os.path.join(ROOT, 'assets/data/contract_ar.txt'), encoding='utf-8').read().strip()
en = open(os.path.join(ROOT, 'assets/data/contract_en.txt'), encoding='utf-8').read().strip()
qs = json.load(open(os.path.join(ROOT, 'assets/data/brief_questions.json'), encoding='utf-8'))['items']

def sq(s): return "'" + s.replace("'", "''") + "'"

head = open(os.path.join(ROOT, 'tools/additions_head.sql'), encoding='utf-8').read()

tpl = []
for sec, title in [('design','عقد خدمة تصميم M.A.K'),('web','عقد خدمة برمجة M.A.K'),('writing','عقد خدمة كتابة M.A.K'),('general','عقد M.A.K الشامل')]:
    tpl.append(f"({sq(sec)}, {sq(title)}, $mak${ar}$mak$, $mak${en}$mak$)")
tpl_sql = """
-- ------------------------------------------------------------
-- 12) قوالب العقد الكاملة (15 مادة، عربي + إنجليزي) — تحدّث القوالب القصيرة في v3
--     المتغيرات {{...}} تُستبدل عند إنشاء العقد من التطبيق.
-- ------------------------------------------------------------
insert into public.contract_templates (section, title, body_ar, body_en)
values
""" + ",\n".join(tpl) + """
on conflict (section, title) do update
set body_ar = excluded.body_ar, body_en = excluded.body_en;
"""

rows = []
for q in qs:
    opts = json.dumps(q['options'], ensure_ascii=False)
    rows.append(f"({sq(q['key'])}, {sq(q['group'])}, {sq(q['ar'])}, {sq(q['en'])}, {sq(q['type'])}, {sq(opts)}::jsonb, true, {q['sort']})")
q_sql = """
-- ------------------------------------------------------------
-- 13) أسئلة البريف الثلاثون (قابلة للتحرير من لوحة المدير)
-- ------------------------------------------------------------
insert into public.brief_questions (key, grp, label_ar, label_en, type, options, active, sort)
values
""" + ",\n".join(rows) + """
on conflict (key) do nothing;

-- ============================================================
-- END OF ADDITIONS V2
-- ============================================================
"""
open(os.path.join(ROOT, 'supabase/schema_v2_additions.sql'), 'w', encoding='utf-8').write(head + tpl_sql + q_sql)
print('ok')
