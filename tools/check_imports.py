#!/usr/bin/env python3
"""يتحقق أن كل رمز معرّف في ملف آخر من المشروع مستورد فعلاً حيث يُستعمل."""
import os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
lib = os.path.join(root, 'lib')
decl = {}   # name -> file
files = {}
for dp, _, fs in os.walk(lib):
    for f in fs:
        if f.endswith('.dart'):
            p = os.path.normpath(os.path.join(dp, f)); files[p] = open(p, encoding='utf-8').read()
pat = re.compile(r"^(?:abstract\s+)?(?:class|enum|typedef|extension\s+(\w+)\s+on|mixin)\s+(\w+)|^(?:final|const|late\s+\w+|late)\s+(?:[\w<>?,\s\(\)]+?\s+)?(\w+)\s*=|^(?:Future<[^>]*>|Future|void|String|bool|int|double|Widget|Color|Map<[^>]*>|List<[^>]*>|Palette|TextStyle|ThemeData|Uint8List|\(\{[^}]*\}\)|\w+\??)\s+(\w+)\s*\(", re.M)
for p, src in files.items():
    for m in re.finditer(r"^(?:abstract\s+)?(?:class|enum|typedef|mixin)\s+(\w+)", src, re.M):
        if not m.group(1).startswith('_'): decl[m.group(1)] = p
    for m in re.finditer(r"^extension\s+(\w+)\s+on", src, re.M): decl[m.group(1)] = p
    for m in re.finditer(r"^(?:Future<[^\n]*?>|[\w<>?,\(\)\{\}]+) (\w+)\([^\n]*(?:=>|\{|;)$", src, re.M):
        n = m.group(1)
        if not n.startswith('_') and n not in ('if','for','while','switch','return','main','build','get','catch'): decl.setdefault(n, p)
    for m in re.finditer(r"^(?:final|const|late) (?:[\w<>?,]+ )?(\w+) ?(?:=|;)", src, re.M):
        if not m.group(1).startswith('_'): decl.setdefault(m.group(1), p)
    for m in re.finditer(r"^(?:[\w<>?,]+)\s+get\s+(\w+)\s*(?:=>|\{)", src, re.M):
        if not m.group(1).startswith('_'): decl.setdefault(m.group(1), p)
bad = 0
for p, src in files.items():
    imps = set()
    for m in re.finditer(r"^(?:import|export) '([^']+)'(?:\s+(show|hide)\s+([^;]+))?;", src, re.M):
        i = m.group(1)
        if i.startswith('package:') or i.startswith('dart:'): continue
        t = os.path.normpath(os.path.join(os.path.dirname(p), i))
        if m.group(2) == 'show':
            for n in re.split(r"\s*,\s*", m.group(3).strip()): imps.add((t, n))
        else: imps.add((t, None))
    code = re.sub(r"//[^\n]*", "", src)
    imported_files = {t for t, n in imps if n is None}
    shown = {(t, n) for t, n in imps if n}
    for name, dfile in decl.items():
        if dfile == p: continue
        if not re.search(r"(?<![\w.$'])" + re.escape(name) + r"(?![\w'])", code): continue
        if dfile in imported_files or any(n == name and t == dfile for t, n in shown): continue
        # قد يكون الاسم محلياً/وسيطاً؛ نبلّغ للتدقيق اليدوي
        print(f"{os.path.relpath(p, root)}: uses '{name}' from {os.path.relpath(dfile, root)} (not imported)"); bad += 1
print('done', bad)
