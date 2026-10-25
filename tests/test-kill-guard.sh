#!/usr/bin/env bash
# Tests for the runtime signal guard (lib/kill_guard.py, kill_guard.sh, lib/shim/*).
#
#   ./tests/test-kill-guard.sh
#
# Never signals a real process of the desktop. The refusals are asked of the guard script,
# which never sends anything. The few end-to-end cases signal only processes this test
# started, each in its own session, and a stand-in for the user manager is injected with
# CAR_GUARD_MANAGER_PID.

set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
GUARD="$ROOT/lib/kill_guard.py"
pass=0; fail=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }
K="ki""ll"; PK="pk""ill"; KA="kill""all"

WORK="$(mktemp -d)"
FAKES=()
cleanup() { for p in "${FAKES[@]:-}"; do [ -n "$p" ] && command $K "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT

# A stand-in for the user manager: its own session, with one child.
fake_manager() {  # $1 = label; prints "manager_pid child_pid"
  setsid bash -c 'sleep 300 & echo $! > "$1"; wait' _ "$WORK/child.$1" >/dev/null 2>&1 &
  local m=$!
  FAKES+=("$m")
  for _ in $(seq 1 50); do [ -s "$WORK/child.$1" ] && break; sleep 0.1; done
  echo "$m $(cat "$WORK/child.$1" 2>/dev/null)"
}
alive() { [ -d "/proc/$1" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null; }

render() {  # $1 = output file, $2 = guard path to bake in
  sed "s|@ROOT@|$ROOT|; s|$ROOT/lib/kill_guard.py|$2|" "$ROOT/lib/kill_guard.sh" > "$1"
}
render "$WORK/guard.sh" "$GUARD"

read -r M C < <(fake_manager one)
export CAR_GUARD_MANAGER_PID="$M"
REAL="$(pgrep -u "$(id -u)" -xo systemd)"

refuses() {  # $1 = label, rest = guard arguments
  local label="$1"; shift
  python3 -I "$GUARD" "$@" >/dev/null 2>&1; local rc=$?
  [ "$rc" = 1 ] && ok "refused: $label" || no "not refused (rc=$rc): $label"
}
allows() {
  local label="$1"; shift
  python3 -I "$GUARD" "$@" >/dev/null 2>&1; local rc=$?
  [ "$rc" = 0 ] && ok "allowed: $label" || no "refused (rc=$rc): $label"
}
GP="$(ps -o ppid= -p "$PPID" | tr -d ' ')"

printf '\n\033[1mThe guard script refuses\033[0m\n'
refuses "the stand-in manager by pid"            $K -TERM "$M"
refuses "the stand-in manager, signal by number" $K -9 "$M"
refuses "the stand-in manager, -s form"          $K -s TERM "$M"
refuses "the stand-in manager, after --"         $K -TERM -- "$M"
refuses "the stand-in manager's process group"   $K -TERM -- "-$M"
refuses "pid 1"                                  $K -HUP 1
refuses "every process"                          $K -9 -1
refuses "something that cannot be read"          $K -TERM abc
refuses "a pattern that matches the stand-in"    $PK -f 'sleep 300'
refuses "every child of the stand-in"            $PK -P "$M"
refuses "every process of the user"              $PK -u "$USER"
refuses "a name that matches the stand-in"       $KA -s TERM bash
[ -n "$REAL" ] && refuses "the real user manager (guard only)" $K -TERM "$REAL"
refuses "the shell's parent, an ancestor"        $K -TERM "$PPID"
refuses "the shell's grandparent, an ancestor"   $K -TERM "$GP"

printf '\n\033[1mThe guard script allows\033[0m\n'
sleep 60 & OWN=$!; FAKES+=("$OWN")
allows "a process this test started"             $K -TERM "$OWN"
allows "listing signals"                         $K -l
allows "a job of the shell"                      $K -TERM %1
allows "a pid that does not exist"               $K -TERM 99999999
allows "a pattern that matches nothing real"     $PK -f '^cartest-nothing-123-'

printf '\n\033[1mEnd to end, with the stand-in manager\033[0m\n'
# The incident: the parent of an orphan is the manager, and the pid was computed at run time.
out="$(bash -c "source '$WORK/guard.sh'; pp=\$(ps -o ppid= -p $C | tr -d ' '); $K \$pp" 2>&1)"; rc=$?
[ "$rc" != 0 ] && alive "$M" && ok "the computed parent of an orphan is refused and survives" \
  || no "computed parent: rc=$rc, manager alive=$(alive "$M" && echo yes || echo no)"
case "$out" in *refused*) ok "the refusal says why" ;; *) no "no reason shown: $out" ;; esac

bash -c "source '$WORK/guard.sh'; $K -TERM $M" >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && alive "$M" && ok "a literal pid of the manager is refused" || no "literal pid: rc=$rc"

bash -c "source '$WORK/guard.sh'; sleep 60 & p=\$!; $K \$p; wait \$p 2>/dev/null; echo done > '$WORK/own'" >/dev/null 2>&1
[ -s "$WORK/own" ] && ok "a process the command started is still signalled" || no "own child was not signalled"

# The shell's parent: an outer shell in its own session runs an inner one that aims at it.
setsid bash -c "bash -c \"source '$WORK/guard.sh'; $K -TERM \\\$PPID; echo \\\$? > '$WORK/anc'\"; echo alive > '$WORK/outer'" >/dev/null 2>&1
[ "$(cat "$WORK/anc" 2>/dev/null)" = 1 ] && [ -s "$WORK/outer" ] \
  && ok "a signal to the parent shell is refused and the parent survives" || no "ancestor case: anc=$(cat "$WORK/anc" 2>/dev/null)"

render "$WORK/missing.sh" "$WORK/not-there.py"
bash -c "source '$WORK/missing.sh'; $K -TERM $M" >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && alive "$M" && ok "fails closed when the guard file is missing" || no "missing guard: rc=$rc"

printf '\n\033[1mShims\033[0m\n'
"$ROOT/lib/shim/$K" -TERM "$M" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && alive "$M" && ok "the shim refuses and the manager survives" || no "shim rc=$rc"
"$ROOT/lib/shim/$PK" -f 'sleep 300' >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && alive "$M" && ok "the pattern shim refuses a pattern that matches it" || no "pattern shim rc=$rc"
"$ROOT/lib/shim/$K" -TERM "$OWN" >/dev/null 2>&1; rc=$?
sleep 0.3
[ "$rc" = 0 ] && ! alive "$OWN" && ok "the shim signals a process the test started" || no "shim own child rc=$rc"

printf '\n\033[1mSabotage: the same scenario without the guard must hurt\033[0m\n'
read -r M2 C2 < <(fake_manager two)
printf '%s\n' "$K() { builtin $K \"\$@\"; }" > "$WORK/off.sh"
CAR_GUARD_MANAGER_PID="$M2" bash -c "source '$WORK/off.sh'; pp=\$(ps -o ppid= -p $C2 | tr -d ' '); $K \$pp" >/dev/null 2>&1
sleep 0.3
! alive "$M2" && ok "with the guard off the stand-in manager dies, so the test can fail" \
  || no "the sabotage did not stop the stand-in: the test would not notice a missing guard"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
