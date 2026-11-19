"""Measured capacity, handed to every session when Martín writes: the model does not know what it did.

Martín, 2026-11-18: «el modelo simplemente no está tan entrenado sabiendo que es una inteligencia
artificial […] si ves lo que ha hecho en cosas de días, te vas a dar cuenta de que su output
simplemente no es humano». Kairós rule 03, "Zero Delays": an estimate anchored to human limits is
a model bias. So each prompt gets two lines measured on this machine over the last 7 days, from
the transcripts of every profile: how long a subagent took, how many ran, how many commits landed.
Cached for 3 hours; computing it reads only the first and last line of each subagent transcript.
"""
import glob
import json
import os
import statistics
import subprocess
import time

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache", "claude-ruta", "capacidad.json")
DAYS = 7


def _ts(line):
    try:
        t = json.loads(line).get("timestamp")
        from datetime import datetime
        return datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _bounds(path):
    try:
        with open(path, "rb") as f:
            first = f.readline()
            f.seek(0, 2); size = f.tell()
            f.seek(max(0, size - 65536))
            tail = f.read().splitlines()
        a = _ts(first)
        b = next((x for x in (_ts(l) for l in reversed(tail)) if x), None)
        return (a, b) if a and b and b >= a else None
    except OSError:
        return None


def measure(now=None):
    now = now or time.time()
    since = now - DAYS * 86400
    durs = []
    for f in glob.glob(os.path.join(HOME, ".claude*", "projects", "*", "*", "subagents", "agent-*.jsonl")):
        try:
            if os.path.getmtime(f) < since:
                continue
        except OSError:
            continue
        b = _bounds(f)
        if b:
            durs.append((b[1] - b[0]) / 60)
    commits = 0
    for repo in glob.glob(os.path.join(HOME, "*", ".git")):
        try:
            out = subprocess.run(["git", "-C", os.path.dirname(repo), "rev-list", "--count", "--all",
                                  f"--since={DAYS}.days"], capture_output=True, text=True, timeout=5).stdout
            commits += int(out.strip() or 0)
        except Exception:
            pass
    d = {"n": len(durs), "commits": commits, "medido": now}
    if durs:
        s = sorted(durs)
        d["mediana"] = round(statistics.median(s), 1)
        d["p90"] = round(s[int(0.9 * (len(s) - 1))], 1)
    return d


def context():
    try:
        d = json.load(open(CACHE))
        if time.time() - d["medido"] > 3 * 3600:
            raise ValueError
    except (OSError, ValueError, KeyError):
        d = measure()
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        json.dump(d, open(CACHE, "w"))
    if not d.get("n"):
        return ""
    med = str(d["mediana"]).replace(".", ","); p90 = str(d["p90"]).replace(".", ",")
    return (f"Medido en esta máquina, últimos {DAYS} días: {d['n']} subagentes, mediana {med} min y p90 {p90} min "
            f"cada uno, varios a la vez; {d['commits']} commits en los repositorios. Una hora que des sale de esas "
            "duraciones y de la ruta crítica (`ruta hora`), no de una jornada humana.")
