#!/usr/bin/env python3
"""Checks every built-in theme's ink (Sources/ThemeInk.swift) against its background (Sources/Themes.swift)
with the WCAG contrast ratio: 4.5:1 for words, 3:1 for list markers, checkboxes and ticked (dimmed) items.
Also fails when a built-in theme has no ink. Run: python3 tests/ink-contrast.py"""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
themes = (root / "Sources/Themes.swift").read_text()
ink = (root / "Sources/ThemeInk.swift").read_text()

bg = dict(re.findall(r'(?:t|signature)\(\s*"([\w-]+)",\s*"[^"]+",\s*"(#[0-9a-fA-F]{6})"', themes))
table = {}
for tid, args in re.findall(r'"([\w-]+)":\s*ThemeInk\.palette\((.*?)\),?\s*$', ink, re.M):
    fields = dict(re.findall(r'(\w+):\s*"(#[0-9a-fA-F]{6})"', args))
    body = re.search(r'body:\s*\[(.*?)\]', args)
    if body:
        for i, h in enumerate(re.findall(r'"(#[0-9a-fA-F]{6})"', body.group(1))):
            fields[f"body{i}"] = h
    table[tid] = fields

def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

LOW = {"marker": 3.0, "checkbox": 3.0, "done": 3.0}
failed = 0
for tid, back in bg.items():
    if tid not in table:
        print(f"FAIL {tid}: no ink"); failed += 1; continue
    worst = 99
    for field, colour in table[tid].items():
        need = LOW.get(field, 4.5)
        r = contrast(colour, back)
        worst = min(worst, r)
        if r < need:
            print(f"FAIL {tid}.{field} {colour} on {back}: {r:.2f} < {need}"); failed += 1
    if "-v" in sys.argv:
        print(f"ok   {tid:18} lowest {worst:.2f}")
for tid in table:
    if tid not in bg:
        print(f"note {tid}: ink but no built-in theme (fine if the theme is coming)")
print(f"{len(bg)} themes, {failed} failures")
sys.exit(1 if failed else 0)
