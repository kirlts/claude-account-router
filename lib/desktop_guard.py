"""Refuses commands that can end the person's whole desktop session.

A process inside a session unit has the systemd user manager as its parent. A `kill $PPID`
there signals the manager, and the manager answers by stopping everything under it: the
desktop, the editor and every Claude session in it. That happened once, from a test, and the
person was working. A rule written down did not prevent it and a test cannot be trusted to
avoid it, so the refusal runs before the command does, in every session of every profile.

Judged from the command text and the live process table, never by running anything.
"""
import os
import re
import shlex

# Processes whose death ends the session. The user manager is the one named `systemd` that is
# not pid 1 and belongs to this user. The editor's main process is the one under the manager.
PROTECTED_COMM = {"kwin_wayland", "kwin_x11", "plasmashell", "startplasma-way", "sddm",
                  "sddm-helper", "dbus-broker", "dbus-daemon", "Xwayland", "gnome-shell"}
SIGNALLERS = {"kill", "pkill", "killall", "skill", "pidwait"}
POWER = {"poweroff", "reboot", "halt", "shutdown", "kexec"}
SHELL_WORDS = {"sudo", "doas", "env", "nohup", "setsid", "exec", "command", "time", "timeout", "nice", "ionice", "xargs"}

MESSAGE = (
    "Blocked: this command can end the whole desktop session ({why}).\n"
    "Signalling the systemd user manager, the desktop, the editor or a parent shell closes every "
    "Claude session and everything the person has open.\n"
    "Signal only a process this command started itself, by the pid it printed, never by $PPID, "
    "by -1, or by a pattern that can match system processes. To stop a unit use "
    "`systemctl --user stop <unit>`."
)


def _procs():
    """(pid, ppid, uid, comm, cmdline) for every live process."""
    out = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat") as f:
                stat = f.read()
            comm = stat[stat.index("(") + 1:stat.rindex(")")]
            ppid = int(stat[stat.rindex(")") + 2:].split()[1])
            uid = os.stat(f"/proc/{name}").st_uid
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
        except (OSError, ValueError):
            continue
        out.append((int(name), ppid, uid, comm, cmd))
    return out


def protected():
    """{pid: description} of the processes that must not be signalled."""
    uid, found = os.getuid(), {1: "pid 1"}
    table = _procs()
    for pid, ppid, puid, comm, cmd in table:
        if comm == "systemd" and puid == uid and pid != 1 and ppid == 1:
            found[pid] = "the systemd user manager"
        elif comm in PROTECTED_COMM and puid in (uid, 0):
            found[pid] = comm
    managers = [p for p, d in found.items() if d == "the systemd user manager"]
    for pid, ppid, puid, comm, cmd in table:
        if puid == uid and ppid in managers and comm in ("code", "electron") and "--type=" not in cmd:
            found[pid] = "the editor"
    return found, table


def _segments(command):
    """Each simple command as a list of words; quoting survives, substitutions stay as text."""
    segs = []
    for part in re.split(r"(?:\|\||&&|[;|&\n])", command):
        try:
            words = shlex.split(part, comments=False, posix=True)
        except ValueError:
            words = part.split()
        if words:
            segs.append(words)
    return segs


def _strip(words):
    while words and (words[0] in SHELL_WORDS or re.fullmatch(r"[A-Za-z_]\w*=.*", words[0])
                     or re.fullmatch(r"-\S*", words[0]) and words[0] != "-"):
        # `timeout 5 cmd` and `nice -n 10 cmd` carry a value; drop one numeric argument too.
        words = words[1:]
        if words and re.fullmatch(r"\d+(\.\d+)?[smhd]?", words[0]):
            words = words[1:]
    return words


def judge(event):
    """None when allowed, or the reason it is refused."""
    tool = event.get("tool_name") or ""
    data = event.get("tool_input") or {}
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        text = " ".join(str(v) for v in data.values() if isinstance(v, str))
        if re.search(r"\bkill\b[^\n;|&]*\$\{?PPID\b", text):
            return "a file that signals $PPID"
        return None
    if tool != "Bash":
        return None
    command = data.get("command") or ""
    if re.search(r"\bkill\b[^\n;|&]*\$\{?PPID\b", command):
        return "it signals $PPID"

    prot, table = protected()
    for words in _segments(command):
        words = _strip(words)
        if not words:
            continue
        name = os.path.basename(words[0])
        rest = words[1:]
        if name in POWER:
            return f"`{name}` powers the machine off"
        if name == "systemctl":
            user = "--user" in rest
            verbs = [w for w in rest if not w.startswith("-")]
            if verbs and verbs[0] in ("poweroff", "reboot", "halt", "kexec", "suspend", "hibernate", "soft-reboot"):
                return f"`systemctl {verbs[0]}`"
            if user and verbs and verbs[0] in ("exit", "kexec"):
                return "`systemctl --user exit` ends the user manager"
            if verbs and verbs[0] in ("stop", "kill", "restart", "disable", "mask") and \
               any(re.search(r"(^|[@\-])(user@|plasma|kwin|sddm|app-com\.microsoft\.VSCode|dbus)", u) for u in verbs[1:]):
                return f"`systemctl {verbs[0]}` on a desktop or editor unit"
        if name == "loginctl" and rest and rest[0] in ("terminate-user", "terminate-session", "kill-user", "kill-session"):
            return f"`loginctl {rest[0]}`"
        if name in SIGNALLERS:
            args = [w for w in rest if not w.startswith("-") or re.fullmatch(r"-\d+", w)]
            if any(w in ("-1", "--", "-0") for w in rest) and name == "kill" and "-1" in rest:
                return "`kill -1` signals every process"
            if name == "kill":
                for w in args:
                    if w.isdigit() and int(w) in prot:
                        return f"it signals {prot[int(w)]} (pid {w})"
                    if re.fullmatch(r"-\d+", w) and rest and w == rest[-1] and w != rest[0]:
                        return "a negative pid signals a process group"
            else:
                # The word after -u, -U or -G names a user or group, not a pattern.
                valued = {"-u", "-U", "-G", "--euid", "--uid", "--group", "-g", "-t", "-P", "-s", "-n", "-o"}
                patterns, skip = [], False
                for w in rest:
                    if skip:
                        skip = False
                    elif w in valued:
                        skip = True
                    elif not w.startswith("-"):
                        patterns.append(w)
                user_wide = any(w in ("-u", "--euid", "--uid", "-U", "-G") for w in rest) and not patterns
                if user_wide:
                    return f"`{name}` by user signals every process of the user"
                for pat in patterns:
                    full = "-f" in rest or "--full" in rest or any(re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", w) for w in rest)
                    try:
                        rx = re.compile(pat)
                    except re.error:
                        continue
                    for pid, desc in prot.items():
                        for p, _pp, _u, comm, cmd in table:
                            if p == pid and (rx.search(cmd) if full else rx.fullmatch(comm) or rx.search(comm) and name == "pkill"):
                                return f"the pattern `{pat}` matches {desc} (pid {pid})"
    # kill $(pgrep ...): the pattern inside the substitution is judged as the pkill it stands for.
    for sub in re.findall(r"(?:\$\(|`)\s*(?:pgrep|pidof)\s+([^)`]*)", command):
        if re.search(r"\bkill\b", command):
            words = sub.split()
            full = any(re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", w) for w in words)
            for pat in [w.strip("'\"") for w in words if not w.startswith("-")]:
                try:
                    rx = re.compile(pat)
                except re.error:
                    continue
                for pid, desc in prot.items():
                    for p, _pp, _u, comm, cmd in table:
                        if p == pid and (rx.search(cmd) if full else rx.fullmatch(comm)):
                            return f"`pgrep {pat}` matches {desc} (pid {pid})"
    return None


def refuse(event):
    """Exit status and message for the hook: 2 with the reason, or 0."""
    why = judge(event)
    if why is None:
        return 0, ""
    return 2, MESSAGE.format(why=why)
