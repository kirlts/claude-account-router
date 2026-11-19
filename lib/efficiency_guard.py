"""Ready steps of the session's route, handed to the session as context. It blocks nothing.

The model waits for what it does not need; on 2026-11-18 a round of judges waited about 45 minutes
for a battery it did not need. bin/ruta records each step, what it depends on and the datum it
takes; when Martín writes, the session is told which steps are ready. Judgment stays with it.
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
    """Never blocks. Kept so the dispatcher's call stays valid.

    2026-11-18: refusing the end of a turn because a declared step was ready is a hook for a
    preference, not for a rule without exceptions (Claude Code best practices: «if you have hooks
    for things that are only preferences, delete them and let Claude decide»; Anthropic's
    constitution: rules make sense when errors are severe, judgment is not robust or there is room
    for manipulation). Ready steps now reach the session as context (`ready_context`)."""
    return 0, ""


def ready_context(session):
    """One line for the prompt context: the steps of this session's route that are ready to start."""
    try:
        mod, d = _route(session)
        r = mod.ready(d)
    except SystemExit:
        return ""
    return ("Pasos de tu ruta listos para arrancar (sus dependencias terminaron): " + ", ".join(r) + ".") if r else ""
