"""Runtime guard for signals: refuses to signal what ends the person's session.

The static guard (desktop_guard.py) reads the command text before it runs. It cannot see a
pid that is computed while the command runs, such as the parent of an orphan, which is the
systemd user manager. This one runs when the signal is about to be sent, with the pids
already resolved, so it holds whatever the text looked like.

Called by the `kill` shell function (kill_guard.sh) and by the `kill`, `pkill` and `killall`
shims in lib/shim. Exit 0 allows, 1 refuses. Anything it cannot resolve refuses.

    kill_guard.py kill  <kill arguments>
    kill_guard.py pkill <pkill arguments>
    kill_guard.py killall <killall arguments>

CAR_GUARD_MANAGER_PID adds one pid to the protected set. It can only widen the refusal, so it
is safe to leave in the environment, and it is how the tests stand in for the real manager.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import desktop_guard  # noqa: E402


def _table():
    return {pid: (ppid, comm) for pid, ppid, _u, comm, _c in desktop_guard._procs()}


def _pgid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            stat = f.read()
        return int(stat[stat.rindex(")") + 2:].split()[2])
    except (OSError, ValueError, IndexError):
        return None


def protected_set(shell_pid):
    """{pid: why} for everything that must not be signalled from the shell `shell_pid`."""
    found, table = desktop_guard.protected()
    found = dict(found)
    extra = os.environ.get("CAR_GUARD_MANAGER_PID", "")
    if extra.isdigit():
        found[int(extra)] = "the systemd user manager"
    procs = _table()
    # Every ancestor of the shell: its parent shell, the claude process, the editor, the manager.
    pid = procs.get(shell_pid, (0, ""))[0]
    seen = 0
    while pid > 1 and seen < 256:
        found.setdefault(pid, f"an ancestor of this shell ({procs.get(pid, (0, '?'))[1]})")
        pid = procs.get(pid, (0, ""))[0]
        seen += 1
    return found


def _groups(found):
    groups = {}
    for pid, why in found.items():
        g = _pgid(pid)
        if g and g > 1:
            groups.setdefault(g, why)
    return groups


def kill_targets(args):
    """Numeric targets of a kill command line. Raises ValueError on a line it cannot read."""
    if not args:
        return []
    first = args[0]
    if first in ("-l", "-L", "--list", "--table", "-t"):
        return []
    i = 0
    if first == "--":
        i = 1
    elif first in ("-s", "-n") or first == "--signal":
        i = 2
    elif first.startswith("--signal="):
        i = 1
    elif re.fullmatch(r"-([0-9]+|[A-Za-z][A-Za-z0-9]*)", first):
        i = 1
    elif first.startswith("-s") or first.startswith("-n"):
        i = 1
    elif first.startswith("-") and first != "-":
        raise ValueError(f"unreadable option {first}")
    if len(args) > i and args[i] == "--":
        i += 1
    out = []
    for a in args[i:]:
        if re.fullmatch(r"-?\d+", a):
            out.append(int(a))
        elif a.startswith("%"):
            continue  # a job of this shell
        else:
            raise ValueError(f"unreadable target {a}")
    return out


def judge_kill(args, shell_pid):
    found = protected_set(shell_pid)
    groups = _groups(found)
    own = _pgid(shell_pid)
    for t in kill_targets(args):
        if t == -1:
            return "it signals every process"
        if t == 0:
            if own and own in groups:
                return f"pid 0 signals this shell's process group, which holds {groups[own]}"
            continue
        if t > 0 and t in found:
            return f"pid {t} is {found[t]}"
        if t < 0 and (-t in found or -t in groups):
            return f"process group {-t} holds {found.get(-t) or groups[-t]}"
        if t == 1 or t == -1:
            return "pid 1"
    return None


def _pgrep(args):
    r = subprocess.run(["pgrep"] + args, capture_output=True, text=True)
    if r.returncode not in (0, 1):
        raise ValueError("pgrep could not resolve the pattern: " + r.stderr.strip())
    return [int(x) for x in r.stdout.split()]


_SIGNAL = re.compile(r"-([0-9]+|[A-Z][A-Z0-9]+)")


def pkill_probe(args):
    """The same selection as pgrep, without the signal."""
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if i == 0 and _SIGNAL.fullmatch(a):
            pass
        elif a == "--signal":
            i += 1
        elif a.startswith("--signal=") or a in ("-e", "--echo"):
            pass
        else:
            out.append(a)
        i += 1
    return out


def judge_pkill(args, shell_pid):
    found = protected_set(shell_pid)
    probe = pkill_probe(args)
    for j, a in enumerate(probe):
        if a in ("-P", "--parent") and j + 1 < len(probe) and probe[j + 1].isdigit() \
           and int(probe[j + 1]) in found:
            return f"it signals every child of {found[int(probe[j + 1])]}"
    if probe and not [a for a in probe if not a.startswith("-")] and \
       any(a in ("-u", "-U", "--euid", "--uid", "-G", "--group") for a in probe):
        return "it signals every process of a user or group"
    if not probe:
        return "it has no selection"
    for pid in _pgrep(probe):
        if pid in found:
            return f"the selection matches pid {pid}, {found[pid]}"
    return None


def judge_killall(args, shell_pid):
    found = protected_set(shell_pid)
    names = [a for a in args if not a.startswith("-")]
    if any(a in ("-u", "--user", "-g", "--process-group") for a in args) and not names:
        return "it signals every process of a user or group"
    if not names:
        return None
    for name in names:
        for pid in _pgrep(["-x", name]):
            if pid in found:
                return f"`{name}` matches pid {pid}, {found[pid]}"
    return None


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("kill guard: missing command, refusing\n")
        return 1
    kind, args = argv[1], argv[2:]
    shell_pid = os.getppid()
    try:
        why = {"kill": judge_kill, "pkill": judge_pkill, "killall": judge_killall}[kind](args, shell_pid)
    except Exception as e:  # cannot resolve: fail closed
        why = f"the target could not be resolved ({e})"
    if why is None:
        return 0
    sys.stderr.write(f"{kind}: refused, {why}.\n"
                     "Signalling the systemd user manager, the desktop, the editor or a parent shell "
                     "closes every Claude session. Signal only a process you started, by the pid it printed.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
