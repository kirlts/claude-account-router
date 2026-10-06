#!/usr/bin/env bash
# Tests for the desktop guard: commands that can end the person's whole session are refused.
#
#   ./tests/test-desktop-guard.sh
#
# Nothing here signals anything. Each case hands the hook an event as text and reads its
# verdict. The dangerous phrases are built from parts so that this file does not trip the
# guard it tests.

set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HOOKS="$ROOT/bin/claude-account-hooks"
pass=0; fail=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }

K="ki""ll"; PK="pk""ill"
MANAGER="$(pgrep -u "$(id -u)" -xo systemd)"

verdict() {  # $1 = tool, $2 = command or file text, [$3 = file path]
  python3 - "$1" "$2" "${3:-}" <<'PY' | "$HOOKS" run >/dev/null 2>&1
import json, sys
tool, text, path = sys.argv[1], sys.argv[2], sys.argv[3]
key = "command" if tool == "Bash" else "content"
inp = {key: text}
if path: inp["file_path"] = path
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": inp, "session_id": "t"}))
PY
  echo $?
}
refused() { [ "$(verdict Bash "$2")" = 2 ] && ok "refused: $1" || no "was allowed: $1 ($2)"; }
allowed() { [ "$(verdict Bash "$2")" = 0 ] && ok "allowed: $1" || no "was refused: $1 ($2)"; }

[ -n "$MANAGER" ] || { echo "no systemd user manager here: skipped"; exit 0; }

printf '\n\033[1mRefused\033[0m\n'
refused "signal to the parent shell"            "$K -TERM \$PPID"
refused "same, braced, inside a pipeline"       "echo x; $K -9 \${PPID} | cat"
refused "inside a here-document of a test"      "cat > t.sh <<'E'
( sh -c '$K -TERM \$PPID' )
E"
refused "the user manager by pid"               "$K -TERM $MANAGER"
refused "the user manager by pid, with sudo"    "sudo $K -9 $MANAGER"
refused "pid 1"                                 "$K -HUP 1"
refused "everything"                            "$K -9 -1"
refused "user manager by name"                  "$PK -x systemd"
refused "the desktop by pattern"                "$PK -f plasmashell"
refused "the compositor by pattern"             "$PK kwin_wayland"
refused "a pattern substitution"                "$K \$(pgrep -f plasmashell)"
refused "everything of the user"                "$PK -u $USER"
refused "user manager exit"                     "systemctl --user exit"
refused "stopping the editor scope"             "systemctl --user stop app-com.microsoft.VSCode-1.scope"
refused "stopping the user manager unit"        "systemctl stop user@1000.service"
refused "terminating the user"                  "loginctl terminate-user $USER"
refused "power off"                             "systemctl poweroff"
refused "reboot"                                "reboot"
refused "after a timeout prefix"                "timeout 5 $K -TERM $MANAGER"

printf '\n\033[1mAllowed\033[0m\n'
allowed "a pid that is not the manager"         "$K -TERM 99999999"
allowed "a test pattern"                        "$PK -f '^cartest123-'"
allowed "stopping a session unit"               "systemctl --user stop claude-session-1-1.service"
allowed "listing the manager"                   "ps -p $MANAGER"
allowed "the word in an echo"                   "echo $K the process later"
allowed "pgrep alone"                           "pgrep -u \$(id -u) -x systemd"
allowed "docker kill"                           "docker $K some-container"
allowed "git with a signal-like word"           "git log --grep='$K'"

printf '\n\033[1mFiles\033[0m\n'
[ "$(verdict Write "( $K -TERM \$PPID )")" = 2 ] && ok "a file that signals the parent is refused" || no "file was allowed"
[ "$(verdict Write "( $K -TERM \$PPID )" /tmp/x.sh)" = 2 ] && ok "a script path is judged the same" || no "script was allowed"
[ "$(verdict Write "Never run $K -TERM \$PPID: it ends the session." /tmp/CLAUDE.md)" = 0 ] \
  && ok "prose that explains the rule is allowed" || no "prose was refused"
[ "$(verdict Write "echo hello")" = 0 ] && ok "an ordinary file is allowed" || no "ordinary file refused"

printf '\n\033[1mThe hook still works for other events\033[0m\n'
out="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"x"}' | "$HOOKS" run 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "a prompt event passes" || no "a prompt event failed: $out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
