#!/usr/bin/env python3
"""Replays a real transcript through the efficiency guard: for every turn end of one day, would the
guard have refused it? Usage: replay-efficiency-guard.py <transcript.jsonl> <YYYY-MM-DD> [--gestion]"""
import json, os, sys, tempfile
from datetime import datetime
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
src, day = sys.argv[1], sys.argv[2]
tmp = tempfile.mkdtemp(dir=os.environ.get("CLAUDE_CODE_TMPDIR"))
os.environ["RUTA_DIR"] = os.path.join(tmp, "ruta")
reg = os.path.join(tmp, "reg"); os.makedirs(reg); os.environ["GESTION_REGISTRO"] = reg
cut = os.path.join(tmp, "t.jsonl")
if "--gestion" in sys.argv:
    json.dump({"sesiones": {"gestion": {"transcripcion": cut}}}, open(os.path.join(reg, "x.json"), "w"))
import efficiency_guard as g
lines = open(src, encoding="utf-8", errors="ignore").readlines()
recs = [json.loads(l) for l in lines]
ends = []
for i, r in enumerate(recs):
    if r.get("type") != "assistant": continue
    c = r["message"].get("content") or []
    if not any(x.get("type") == "text" and x.get("text", "").strip() for x in c): continue
    nxt = next((recs[j] for j in range(i + 1, len(recs)) if recs[j].get("type") in ("user", "assistant")), None)
    if nxt and nxt.get("type") == "assistant": continue
    ts = datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00")).astimezone()
    if ts.strftime("%Y-%m-%d") == day: ends.append((i, ts))
tot = {"turnos": 0, "hora sin ruta": 0, "a un director sin cambio": 0}
ej = {}
for i, ts in ends:
    open(cut, "w").writelines(lines[: i + 1])
    os.environ["RUTA_AHORA"] = str(ts.timestamp())
    st, msg = g.check({"hook_event_name": "Stop", "session_id": "replay", "transcript_path": cut})
    tot["turnos"] += 1
    if st is None:
        k = "hora sin ruta" if msg.startswith("Blocked: ") and "future hour" in msg else "a un director sin cambio"
        tot[k] += 1
        txt = [x["text"] for x in recs[i]["message"]["content"] if x.get("type") == "text"][-1]
        ej.setdefault(k, []).append(f"{ts:%H:%M} {txt[:110]!r}")
print(json.dumps(tot, ensure_ascii=False))
for k, v in ej.items():
    print(f"-- {k}: {len(v)}"); [print("  ", x) for x in v[:6]]
    hit = [x for x in v if x.startswith("21:2")]
    if hit: print("   21:2x:", hit)
