#!/usr/bin/env bash
# Tests for the session unit: what a session starts dies with it, without a watcher.
#
#   ./tests/test-session-unit.sh
#
# Needs a systemd user manager, because the guarantee under test is systemd's.
# Without one the file reports that it was skipped and passes: the router then
# launches directly, which test 6 covers wherever the manager does exist.
# Config and profiles live in a throwaway HOME; the units are real, are named
# after this run, and are stopped at the end.

set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROUTER="$ROOT/bin/claude-account-router"
SESSION="$ROOT/bin/claude-session"

pass=0; fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if ! command -v systemd-run >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
  printf 'skipped: no systemd user manager here\n'
  exit 0
fi

REAL_HOME="$HOME"
SANDBOX="$(mktemp -d)"
TAG="cartest$$"
export HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/home/.config"
export CLAUDE_ROUTER_STOP_TIMEOUT=2
WORK="$SANDBOX/work"; OUT="$SANDBOX/out"
mkdir -p "$HOME/.claude" "$XDG_CONFIG_HOME/claude-account-router" "$WORK" "$OUT"
printf 'profile default ~/.claude\n' >"$XDG_CONFIG_HOME/claude-account-router/routes.conf"
LOG="$XDG_CONFIG_HOME/claude-account-router/router.log"

cleanup() {
  local u
  for u in $(systemctl --user list-units --all --no-legend --plain 'claude-session-*' 'claude-detached-*' 2>/dev/null | awk '{print $1}'); do
    systemctl --user show -p Environment --value "$u" 2>/dev/null | grep -q "CARTEST_TAG=$TAG" \
      && systemctl --user stop "$u" 2>/dev/null
  done
  pkill -9 -f "^$TAG-" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT
export CARTEST_TAG="$TAG"

# Anchored: the launchers carry these names as arguments, and only the renamed
# process has one at the start of its command line.
strays() { pgrep -fc "^$TAG-$1-" || true; }
wait_until() {  # $1 = seconds, rest = command that must succeed
  local limit=$(( $(date +%s) + $1 )); shift
  while [ "$(date +%s)" -le "$limit" ]; do "$@" && return 0; sleep 0.1; done
  return 1
}
no_strays() { [ "$(strays "$1")" = 0 ]; }

# A stand-in for Claude. It leaves behind the kinds of process a real session does.
cat >"$SANDBOX/fake-session" <<'EOF'
#!/usr/bin/env bash
id="$1"; out="$2"; shift 2
t="$CARTEST_TAG-$id"
bash -c "exec -a $t-child sleep 9001" &
setsid bash -c "exec -a $t-setsid sleep 9002" </dev/null >/dev/null 2>&1 &
nohup bash -c "exec -a $t-nohup tail -f /dev/null" </dev/null >/dev/null 2>&1 &
( setsid bash -c "exec -a $t-double sleep 9003" </dev/null >/dev/null 2>&1 & )
bash -c "trap '' TERM; exec -a $t-stubborn sleep 9004" &
[ $# -gt 0 ] && "$@"
printf '%s\n' "$$" >"$out/$id.pid"
exec -a "$t-main" sleep 9000
EOF
chmod +x "$SANDBOX/fake-session"

launch() {  # $1 = id, rest = extra command run inside the session
  local id="$1"; shift
  ( cd "$WORK" && "$ROUTER" "$SANDBOX/fake-session" "$id" "$OUT" "$@" </dev/null >/dev/null 2>&1 ) &
  wait_until 10 test -s "$OUT/$id.pid"
}

head_ "1. The launched process runs inside a session unit"
got="$(cd "$WORK" && printf 'ping\n' | CLAUDE_CONFIG_DIR_PROBE=kept "$ROUTER" bash -c \
  'read -r line; printf "%s|%s|%s|%s" "$line" "$CAR_SESSION_UNIT" "$CLAUDE_CONFIG_DIR_PROBE" "$(cut -d: -f3 /proc/self/cgroup)"')"
IFS='|' read -r in_line unit probe cgroup <<<"$got"
[ "$in_line" = ping ] && ok "stdin and stdout pass through" || no "stdin/stdout did not pass through: $got"
[[ "$unit" == claude-session-*.service ]] && ok "CAR_SESSION_UNIT names the unit" || no "CAR_SESSION_UNIT is '$unit'"
[[ "$cgroup" == *"/$unit" ]] && ok "the process is in that unit's cgroup" || no "cgroup is '$cgroup'"
[ "$probe" = kept ] && ok "the caller's environment reaches the unit" || no "environment lost: '$probe'"

# systemd expands ${NAME} in a unit's command line unless told not to. A prompt
# is an argument, and prompts mention variables.
args_in=('${HOME}' '$PATH and 100%' "it's \"quoted\"" $'two\nlines' '%n %%' '')
got="$(cd "$WORK" && "$ROUTER" bash -c 'printf "%s\037" "$@"' _ "${args_in[@]}" </dev/null)"
want="$(printf '%s\037' "${args_in[@]}")"
[ "$got" = "$want" ] && ok "arguments with \$, %, quotes and a newline arrive unchanged" \
  || no "arguments were rewritten on the way in: $(printf '%q' "$got")"

head_ "2. The exit status is the launched command's"
( cd "$WORK" && "$ROUTER" bash -c 'exit 7' </dev/null ); rc=$?
[ "$rc" = 7 ] && ok "exit 7 comes back as 7" || no "exit 7 came back as $rc"
( cd "$WORK" && "$ROUTER" bash -c 'exit 125' </dev/null ); rc=$?
[ "$rc" = 125 ] && ok "exit 125 comes back as 125, not as a second launch" || no "exit 125 came back as $rc"

head_ "3. SIGKILL to the session leaves nothing behind"
launch kill9
before="$(strays kill9)"
[ "$before" = 6 ] && ok "six processes before the kill" || no "expected 6 processes before the kill, found $before"
kill -9 "$(cat "$OUT/kill9.pid")"
wait_until 8 no_strays kill9 && ok "none left after SIGKILL, the one that ignores SIGTERM included" \
  || no "$(strays kill9) process(es) survived SIGKILL of the session"

head_ "4. SIGTERM to the router stops the unit"
launch term
router_pid="$(pgrep -f "claude-account-router $SANDBOX/fake-session term " | head -1)"
kill -TERM "$router_pid"
wait_until 8 no_strays term && ok "none left after SIGTERM to the router" \
  || no "$(strays term) process(es) survived SIGTERM to the router"

head_ "5. CLAUDE_ROUTER_NO_UNIT=1 launches directly"
got="$(cd "$WORK" && CLAUDE_ROUTER_NO_UNIT=1 "$ROUTER" bash -c 'printf "%s|%s" "${CAR_SESSION_UNIT-unset}" "$(cut -d: -f3 /proc/self/cgroup)"' </dev/null)"
[[ "$got" == unset\|* ]] && [[ "$got" != *claude-session-* ]] && ok "no unit, same command" || no "switch ignored: $got"
grep -q 'no session unit (CLAUDE_ROUTER_NO_UNIT=1)' "$LOG" && ok "the log says why" || no "the log does not say why"

head_ "6. A unit that cannot start does not stop the launch"
mkdir -p "$SANDBOX/broken"
printf '#!/bin/sh\nexit 1\n' >"$SANDBOX/broken/systemd-run"; chmod +x "$SANDBOX/broken/systemd-run"
got="$(cd "$WORK" && PATH="$SANDBOX/broken:$PATH" "$ROUTER" bash -c 'printf ran' </dev/null)"
[ "$got" = ran ] && ok "the command ran directly" || no "the command did not run: '$got'"
grep -q 'session unit did not start' "$LOG" && ok "the log records the fallback" || no "the fallback was not logged"

head_ "7. on-end runs once, when the session ends"
launch onend "$SESSION" on-end mark -- touch "$OUT/onend.ran"
[ ! -e "$OUT/onend.ran" ] && ok "nothing runs while the session is alive" || no "the command ran before the session ended"
kill -9 "$(cat "$OUT/onend.pid")"
wait_until 8 test -e "$OUT/onend.ran" && ok "it ran after SIGKILL of the session" || no "it never ran"
left="$(systemctl --user list-units --all --no-legend --plain 'claude-session-*-end-mark*' | wc -l)"
[ "$left" = 0 ] && ok "its unit is gone" || no "$left on-end unit(s) left"

head_ "8. on-end outside a session says so"
( unset CAR_SESSION_UNIT; "$SESSION" on-end x -- true ) 2>/dev/null; rc=$?
[ "$rc" = 3 ] && ok "exit 3 without a session unit" || no "expected 3, got $rc"
CAR_SESSION_UNIT=claude-session-0-0.service "$SESSION" on-end x -- true 2>/dev/null; rc=$?
[ "$rc" = 3 ] && ok "exit 3 when the named session is not active" || no "expected 3, got $rc"

head_ "9. detach outlives the session and respects --max"
launch detach "$SESSION" detach job --max 60 -- bash -c "exec -a $TAG-detached-long sleep 9005"
kill -9 "$(cat "$OUT/detach.pid")"
wait_until 8 no_strays detach
[ "$(pgrep -fc "^$TAG-detached-long")" = 1 ] && ok "the detached command is alive after the session died" \
  || no "the detached command did not survive"
pkill -f "^$TAG-detached-long"
( cd "$WORK" && "$SESSION" detach short --max 1 -- bash -c "exec -a $TAG-detached-short sleep 9006" >/dev/null )
gone() { [ "$(pgrep -fc "^$TAG-detached-short")" = 0 ]; }
wait_until 6 gone && ok "--max 1 ends it" || no "the command outlived --max 1"
"$SESSION" detach nomax -- true 2>/dev/null; rc=$?
[ "$rc" = 64 ] && ok "detach without --max is refused" || no "expected 64, got $rc"

head_ "10. A router started inside a session belongs to it"
launch outer bash -c "cd '$WORK' && '$ROUTER' bash -c 'exec -a $TAG-inner-main sleep 9007' </dev/null >/dev/null 2>&1 &"
inner() { [ "$(pgrep -fc "^$TAG-inner-main")" = 1 ]; }
wait_until 8 inner && ok "the inner launch is running" || no "the inner launch did not start"
inner_cg="$(cut -d: -f3 "/proc/$(pgrep -f "^$TAG-inner-main" | head -1)/cgroup" 2>/dev/null)"
outer_cg="$(cut -d: -f3 "/proc/$(cat "$OUT/outer.pid")/cgroup" 2>/dev/null)"
[ -n "$inner_cg" ] && [ "$inner_cg" != "$outer_cg" ] && ok "it has a unit of its own" || no "inner and outer share a cgroup"
kill -9 "$(cat "$OUT/outer.pid")"
inner_gone() { [ "$(pgrep -fc "^$TAG-inner-main")" = 0 ]; }
wait_until 8 inner_gone && ok "it died with the outer session" || no "the inner launch survived the outer session"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
