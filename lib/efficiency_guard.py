"""Efficiency guard: a step of the session's route that is ready is started.

Why (2026-11-18): the model waits for what it does not need. That day a round of judges waited
about 45 minutes for a test battery it did not need, with free capacity announced three times.
Each step of bin/ruta declares what it depends on and the datum it takes from it; at the end of a
turn, a step whose dependencies are done, that did not start and has no measured limit
(`ruta limite`) refuses the end of the turn.

It reads only the route the session declared, never the words of the model or of Martín: «no hay
que poner lenguajes de programación que evalúen texto verbatim» (Martín, 2026-11-18).
# se-retira-cuando: in three assignments it refuses nothing, or Martín drops the route.
"""
import glob
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
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










READY_MSG = ("Blocked: {steps} has every dependency done and did not start. It does not depend on what you are "
             "waiting for: start it now (`ruta inicia <id>`). If a real limit stops it, declare it with the measurement: "
             "`ruta limite <id> --dato \"<free memory or quota reset, with the number>\"`.")


def check(event):
    """(None, reason) to block a Stop; (0, "") otherwise.

    Martín, 2026-11-18 22:0x: «no hay que poner lenguajes de programación que evalúen texto verbatim».
    The hour check and the management check read the model's words and were removed. What stays reads
    only the route the session declared: a ready step that did not start."""
    if event.get("hook_event_name") != "Stop" or event.get("stop_hook_active"):
        return 0, ""
    try:
        mod, d = _route(str(event.get("session_id") or ""))
        ready = mod.ready(d)
    except SystemExit:
        ready = []
    if ready:
        return None, READY_MSG.format(steps=", ".join(ready))
    return 0, ""
