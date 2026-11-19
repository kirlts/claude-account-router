"""Efficiency guard: an hour comes from a critical path, a ready step is started, and the session
that manages for Martín does not talk to him about nothing.

Why (2026-11-18): the model does not know it is an AI. It estimates with a human working day, adds
steps in series that do not depend on each other and waits for what it does not need (Kairós,
README "Erradicación del sesgo de compresión"; rule 03 "Zero Delays"; ~/Escritorio/AI/LLMs_
Ejecución vs. Comunicación.md). Between 2026-10-18 and 2026-11-18 Martín corrected it by hand 79
times, in 23 sessions of two accounts. That day a round of judges waited about 45 minutes for a
test battery it did not need, with free capacity announced three times. A rule written down did not
change it; this runs in every session of every profile, through claude-account-hooks.

  A. Stop and SendMessage: a future hour (HH:MM) must be the finish of a step of this session's
     route (bin/ruta), within 3 minutes, or come from a message Martín typed. Otherwise refused.
  B. Stop: a step of the route whose dependencies are done and that did not start, without a
     measured limit (`ruta limite`), refuses the end of the turn.
  C. Stop, only in the session registered as management (~/.cache/okos/gestion/*.json): a turn
     Martín did not start whose text changes no hour, delivers no link and asks nothing is refused:
     a director is not told that nothing changed. A turn that answers Martín always passes.

Judged from the transcript, the route file and the registry. Never runs anything.
# se-retira-cuando: in three assignments Martín does not complain about time or slowness and the
# guard did not refuse anything (Kairós IMK 3.2 and 3.3 as the measure of the human side).
"""
import glob
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
HOUR = re.compile(r"(?<![\d:/.])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])(?!\s?[aApP]\.?[mM])")  # 1:20am is a quota reset, not an estimate
REGISTRY = os.environ.get("GESTION_REGISTRO", os.path.join(HOME, ".cache", "okos", "gestion"))
TOLERANCE = 3 * 60
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin"))


def _now():
    return float(os.environ.get("RUTA_AHORA") or time.time())


def _route(session):
    import importlib.machinery, importlib.util
    p = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin", "ruta")
    loader = importlib.machinery.SourceFileLoader("ruta_mod", p)
    spec = importlib.util.spec_from_loader("ruta_mod", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m, m.load(session)


def _text(content):
    if isinstance(content, str):
        return content
    return "\n".join(x.get("text", "") for x in content or [] if isinstance(x, dict) and x.get("type") == "text")


def _typed_by_person(r):
    if r.get("type") != "user" or r.get("isMeta"):
        return False
    c = (r.get("message") or {}).get("content")
    if isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
        return False
    t = _text(c).strip()
    return bool(t) and not t.startswith(("<", "Another Claude", "Stop hook", "[Request", "This session is being continued", "[SYSTEM")) \
        and "cross-session-message" not in t[:300] and "task-notification" not in t[:300]


def _turn(path):
    """(texts of the last turn, did Martín start it, hours Martín typed recently, hours in earlier texts)."""
    try:
        rs = [json.loads(l) for l in open(path, encoding="utf-8", errors="ignore") if l.strip()]
    except (OSError, ValueError):
        return [], True, set(), set()
    start, by_person = 0, True
    for i in range(len(rs) - 1, -1, -1):
        r = rs[i]
        if r.get("type") == "user" and not r.get("isMeta"):
            c = (r.get("message") or {}).get("content")
            if isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
                continue
            start, by_person = i, _typed_by_person(r)
            break
    texts = [_text((r.get("message") or {}).get("content")) for r in rs[start:] if r.get("type") == "assistant"]
    texts = [t for t in texts if t.strip() and not t.startswith("You've hit your")]  # quota notices are not the model's
    typed, earlier = set(), set()
    for r in rs[max(0, start - 400):start + 1]:
        t = _text((r.get("message") or {}).get("content"))
        if _typed_by_person(r):
            typed |= {f"{int(h):02d}:{m}" for h, m in HOUR.findall(t)}
        elif r.get("type") == "assistant":
            earlier |= {f"{int(h):02d}:{m}" for h, m in HOUR.findall(t)}
    return texts, by_person, typed, earlier


def _future(text):
    now = datetime.fromtimestamp(_now())
    out = []
    for h, m in HOUR.findall(text):
        t = now.replace(hour=int(h), minute=int(m), second=0, microsecond=0)
        if t < now - timedelta(minutes=1):
            t += timedelta(days=1)
        if now + timedelta(minutes=1) < t < now + timedelta(hours=20):
            out.append((f"{int(h):02d}:{m}", t.timestamp()))
    return out


def _unmatched_hours(text, session, typed):
    hours = [(s, t) for s, t in _future(text) if s not in typed]
    if not hours:
        return []
    try:
        mod, d = _route(session)
        fins = list(mod.schedule(d).values()) if d.get("pasos") else []
    except SystemExit:
        fins = []
    return [s for s, t in hours if not any(abs(t - f) <= TOLERANCE for f in fins)]


def _is_management(transcript):
    for f in glob.glob(os.path.join(REGISTRY, "*.json")):
        if f.endswith(".duraciones.json"):
            continue
        try:
            d = json.load(open(f))
        except (OSError, ValueError):
            continue
        if transcript and transcript in (d.get("pm"), ((d.get("sesiones") or {}).get("gestion") or {}).get("transcripcion")):
            return True
    return False


HOUR_MSG = ("Blocked: {hours} is a future hour that does not come from a critical path.\n"
            "An hour is the finish of measured steps, not a sum of them: `ruta paso <id> --min <measured> "
            "--fuente <where it was measured> [--depende <id> --necesita \"<datum>\"]`, then `ruta hora`. "
            "Steps that do not depend on each other run at the same time. A duration already measured (a judge "
            "already run, a deploy, a battery) enters as a step with that source. Then write the hour `ruta hora` gives.")
READY_MSG = ("Blocked: {steps} has every dependency done and did not start. It does not depend on what you are "
             "waiting for: start it now (`ruta inicia <id>`). If a real limit stops it, declare it with the measurement: "
             "`ruta limite <id> --dato \"<free memory or quota reset, with the number>\"`.")
MGMT_MSG = ("Blocked: this turn was not started by Martín, and its text changes no hour, delivers nothing he can open "
            "and asks him nothing. A director is not told that nothing changed. End the turn without text; write to him "
            "only when an hour moves, something is ready to open, or a decision is his.")


def check(event):
    """(status, message) for a PreToolUse event; (None, reason) to block a Stop."""
    name = event.get("hook_event_name")
    session = str(event.get("session_id") or "")
    transcript = event.get("transcript_path") or ""
    if name == "PreToolUse" and event.get("tool_name") == "SendMessage":
        msg = str((event.get("tool_input") or {}).get("message") or "")
        _, _, typed, _ = _turn(transcript)
        bad = _unmatched_hours(msg, session, typed)
        if bad:
            return 2, HOUR_MSG.format(hours=", ".join(bad))
        return 0, ""
    if name != "Stop" or event.get("stop_hook_active"):
        return 0, ""
    texts, by_person, typed, earlier = _turn(transcript)
    final = texts[-1] if texts else ""
    bad = _unmatched_hours(final, session, typed)
    if bad:
        return None, HOUR_MSG.format(hours=", ".join(bad))
    try:
        mod, d = _route(session)
        ready = mod.ready(d)
    except SystemExit:
        ready = []
    if ready:
        return None, READY_MSG.format(steps=", ".join(ready))
    if final.strip() and not by_person and _is_management(transcript):
        hours = {s for s, _ in _future(final)}
        if not (hours - earlier) and not re.search(r"https?://", final) and "?" not in final:
            return None, MGMT_MSG
    return 0, ""
