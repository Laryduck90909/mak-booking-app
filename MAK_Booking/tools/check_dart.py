#!/usr/bin/env python3
"""فحص بدائي لملفات Dart (لا يغني عن flutter analyze): توازن الأقواس + وجود الملفات المستوردة."""
import os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
lib = os.path.join(root, 'lib')
errs = 0

def strip(src):
    out = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            while i < n and src[i] != '\n': i += 1
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2); i = n if j < 0 else j + 2; continue
        if c in '\'"':
            raw = i > 0 and src[i-1] == 'r'
            triple = src.startswith(c*3, i)
            q = c*3 if triple else c
            i += len(q)
            depth_stack = []
            while i < n:
                if not raw and src[i] == '\\': i += 2; continue
                if src.startswith(q, i): i += len(q); break
                if not raw and src.startswith('${', i):
                    # interpolation: keep content, counted for balance
                    d = 1; j = i + 2
                    inner = []
                    while j < n and d:
                        if src[j] == '{': d += 1
                        elif src[j] == '}': d -= 1
                        if d: inner.append(src[j])
                        j += 1
                    out.append('(' + strip(''.join(inner)) + ')')
                    i = j; continue
                i += 1
            out.append('""'); continue
        out.append(c); i += 1
    return ''.join(out)

pairs = {')': '(', ']': '[', '}': '{'}
for dp, _, fs in os.walk(lib):
    for f in fs:
        if not f.endswith('.dart'): continue
        path = os.path.join(dp, f)
        src = open(path, encoding='utf-8').read()
        s = strip(src)
        st = []
        line = 1
        bad = False
        for ch in s:
            if ch == '\n': line += 1
            if ch in '([{': st.append((ch, line))
            elif ch in ')]}':
                if not st or st[-1][0] != pairs[ch]:
                    print(f'UNBALANCED {os.path.relpath(path, root)} near line {line}: {ch}'); bad = True; errs += 1; break
                st.pop()
        if not bad and st:
            print(f'UNCLOSED {os.path.relpath(path, root)}: {st[-1]}'); errs += 1
        for m in re.finditer(r"^(?:import|export) '([^']+)'", src, re.M):
            imp = m.group(1)
            if imp.startswith('package:') or imp.startswith('dart:'):
                if imp.startswith('package:mak_booking'):
                    t = os.path.join(lib, imp.split('/', 1)[1])
                    if not os.path.exists(t): print(f'MISSING import {imp} in {f}'); errs += 1
                continue
            t = os.path.normpath(os.path.join(dp, imp))
            if not os.path.exists(t):
                print(f'MISSING import {imp} in {os.path.relpath(path, root)}'); errs += 1
print('OK' if errs == 0 else f'{errs} problem(s)')
sys.exit(1 if errs else 0)
