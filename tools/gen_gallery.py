#!/usr/bin/env python3
"""Generate tools/color-test-gallery.html from Photos/manifest.json by running
each photo through the pipeline (tools/test_bank.py). Re-run after changing the
manifest or tuning the detector.  Usage:  python3 tools/gen_gallery.py"""
import json, html, importlib.util, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("tb", os.path.join(ROOT, "tools", "test_bank.py"))
tb = importlib.util.module_from_spec(spec); spec.loader.exec_module(tb)

SW = {"red":"#E62929","orange":"#FF8C00","yellow":"#FFD91A","green":"#29BD4D","blue":"#2173F2",
      "purple":"#9940D9","pink":"#FF73B3","white":"#FFFFFF","black":"#111111"}
INK = {"yellow":"#000","white":"#000","pink":"#000"}
COLORS = list(SW)

tests = json.load(open(os.path.join(ROOT, "Photos", "manifest.json")))["tests"]
data = []
for t in tests:
    hsvs = tb.downsample(os.path.join(ROOT, "Photos", t["file"]))
    sc = {c: tb.analyze(hsvs, c) for c in tb.COLORS}
    passed = [c for c in tb.COLORS if sc[c][2]]
    data.append({"file": t["file"], "label": t["label"], "expect_pass": t["expect_pass"],
                 "passed": passed, "scores": {c: [sc[c][0]*100, sc[c][1]*100] for c in tb.COLORS},
                 "ok": all(c in passed for c in t["expect_pass"]) and all(c not in passed for c in t.get("expect_fail", [])),
                 "license": t.get("license",""), "attribution": t.get("attribution",""), "source": t.get("source","")})

n = len(data); ok = sum(d["ok"] for d in data)
from collections import Counter
per = Counter(d["expect_pass"][0] for d in data)

def chip(c, star=False):
    return f'<span class="chip{" star" if star else ""}" style="background:{SW[c]};color:{INK.get(c,"#fff")}">{"★ " if star else ""}{c}</span>'

cards = []
for d in data:
    img = html.escape("../Photos/" + d["file"]); want = set(d["expect_pass"])
    exp = "".join(chip(c) for c in d["expect_pass"])
    sel = "".join(chip(c, c in want) for c in d["passed"]) or '<span class="none">(none)</span>'
    rows = ""
    for c in COLORS:
        mf, bf = d["scores"][c]; p = c in d["passed"]
        rows += (f'<div class="srow{" tgt" if c in want else ""}"><span class="sname">{c}</span>'
                 f'<span class="bar"><i style="width:{min(mf,100):.0f}%;background:{SW[c]}"></i></span>'
                 f'<span class="snum">{mf:.0f}%·{bf:.0f}%</span>{"<b class=pass>PASS</b>" if p else ""}</div>')
    badge = '<span class="ok">✓</span>' if d["ok"] else '<span class="bad">✗</span>'
    src = html.escape(d["source"]); lic = html.escape(d["license"]); attr = html.escape(d["attribution"])
    credit = (f'<a href="{src}" target="_blank">{lic}</a> · {attr}' if src else (lic or "own photo"))
    cards.append(f'''<article class="card" data-target="{d['expect_pass'][0]}">
  <div class="photo"><img loading="lazy" src="{img}" alt="{html.escape(d['label'])}"></div>
  <div class="meta"><div class="cap">{html.escape(d['label'])} {badge}</div>
    <div class="line"><span class="lbl">expected</span>{exp}</div>
    <div class="line"><span class="lbl">app picked</span>{sel}</div>
    <details><summary>all 9 scores (match%·blob%)</summary><div class="scores">{rows}</div></details>
    <div class="credit">{credit}</div></div></article>''')

filters = '<button class="f active" data-f="all">all</button>' + "".join(
    f'<button class="f" data-f="{c}" style="--c:{SW[c]}">{c} {per[c]}</button>' for c in COLORS)

doc = f'''<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>I Spy: Colors — Test Bank Gallery</title><style>
 :root{{color-scheme:light dark}}
 body{{font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;margin:0 auto;max-width:1200px;padding:18px 20px 60px}}
 h1{{font-size:1.4rem;margin:0 0 2px}} .sub{{color:#888;margin:0 0 14px}}
 .summary{{font-weight:700}} .summary .g{{color:#18a558}}
 .filters{{display:flex;flex-wrap:wrap;gap:6px;margin:12px 0 18px}}
 .f{{font:inherit;font-size:.8rem;text-transform:capitalize;padding:4px 12px;border-radius:999px;border:1px solid #8886;background:transparent;cursor:pointer}}
 .f.active{{background:#8883;font-weight:700}}
 .f[data-f]:not([data-f=all]):before{{content:"";display:inline-block;width:9px;height:9px;border-radius:50%;background:var(--c);margin-right:6px;vertical-align:-1px;border:1px solid #0003}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:16px}}
 .card{{border:1px solid #8884;border-radius:14px;overflow:hidden;background:#8881;display:flex;flex-direction:column}}
 .photo{{aspect-ratio:4/3;background:conic-gradient(#0000 90deg,#8882 0 180deg,#0000 0 270deg,#8882 0) 0 0/22px 22px;display:flex;align-items:center;justify-content:center}}
 .photo img{{width:100%;height:100%;object-fit:contain}}
 .meta{{padding:10px 12px 12px;display:flex;flex-direction:column;gap:7px}}
 .cap{{font-weight:600;font-size:.9rem;line-height:1.25}}
 .line{{display:flex;flex-wrap:wrap;gap:5px;align-items:center}}
 .lbl{{font-size:.7rem;text-transform:uppercase;letter-spacing:.04em;color:#888;width:62px;flex:none}}
 .chip{{font-size:.78rem;text-transform:capitalize;padding:2px 9px;border-radius:999px;border:1px solid #0003;font-weight:600}}
 .chip.star{{box-shadow:0 0 0 2px #18a558}} .none{{color:#999;font-style:italic;font-size:.8rem}}
 .ok{{color:#18a558;font-weight:700;float:right}} .bad{{color:#c0392b;font-weight:700;float:right}}
 details{{font-size:.78rem}} summary{{cursor:pointer;color:#888}}
 .scores{{margin-top:6px;display:flex;flex-direction:column;gap:3px}}
 .srow{{display:flex;align-items:center;gap:6px}} .srow.tgt{{font-weight:700}}
 .sname{{width:52px;text-transform:capitalize;font-size:.74rem}}
 .bar{{flex:1;height:9px;background:#8882;border-radius:5px;overflow:hidden}} .bar i{{display:block;height:100%}}
 .snum{{width:62px;text-align:right;font-variant-numeric:tabular-nums;color:#888;font-size:.72rem}}
 .pass{{color:#18a558;font-size:.66rem;width:34px}}
 .credit{{font-size:.68rem;color:#999;margin-top:2px}} .credit a{{color:#888}}
</style></head><body>
<h1>🔍 I Spy: Colors — Test Bank Gallery</h1>
<p class="sub">Every real-photo test, the color it's labeled with, and what the detector actually selected. ★ marks the expected color.</p>
<p class="summary"><span class="g">{ok}/{n}</span> photos: the expected color was found in all of them. Extra chips = real-world background/highlight noise (white backdrops, warm highlights, busy scenes).</p>
<div class="filters">{filters}</div>
<div class="grid">{''.join(cards)}</div>
<script>
 const btns=[...document.querySelectorAll('.f')],cards=[...document.querySelectorAll('.card')];
 btns.forEach(b=>b.onclick=()=>{{btns.forEach(x=>x.classList.remove('active'));b.classList.add('active');
   const f=b.dataset.f;cards.forEach(c=>c.style.display=(f==='all'||c.dataset.target===f)?'':'none');}});
</script></body></html>'''
open(os.path.join(ROOT, "tools", "color-test-gallery.html"), "w").write(doc)
print(f"wrote tools/color-test-gallery.html — {n} photos, {ok}/{n} ok")
print("per color:", dict(per))
