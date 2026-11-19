#!/usr/bin/env bash
# Tests for the efficiency guard and bin/ruta: hours from a critical path, ready steps started,
# no empty reports to a director. Each case hands the hook an event as text and reads its verdict.
#
#   ./tests/test-efficiency-guard.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HOOKS="$ROOT/bin/claude-account-hooks"; RUTA="$ROOT/bin/ruta"
T=$(mktemp -d "${CLAUDE_CODE_TMPDIR:-$HOME/.cache/claude-tmp}/prueba-eficiencia.XXXX"); trap 'rm -rf "$T"' EXIT
export RUTA_DIR="$T/ruta" RUTA_SESION="s1" GESTION_REGISTRO="$T/reg" RUTA_AHORA=$(date -d 'today 21:00' +%s)
mkdir -p "$T/reg"
pass=0; fail=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }
iso() { date -u -d "@$(date -d "today $1" +%s)" +%Y-%m-%dT%H:%M:%S.000Z; }
# transcript: lines "u|text" (typed by Martín), "n|text" (a notification), "a|HH:MM|text" (assistant)
tr() { local f="$T/$1.jsonl"; shift; : > "$f"; for l in "$@"; do
  case "$l" in
    u\|*) jq -nc --arg x "${l#u|}" '{type:"user",message:{content:$x}}' ;;
    n\|*) jq -nc --arg x "${l#n|}" '{type:"user",message:{content:("<task-notification>"+$x+"</task-notification>")}}' ;;
    a\|*) h=${l#a|}; h=${h%%|*}; jq -nc --arg t "$(iso "$h")" --arg x "${l#a|*|}" '{type:"assistant",timestamp:$t,message:{content:[{type:"text",text:$x}]}}' ;;
  esac >> "$f"; done; echo "$f"; }
stop() { jq -nc --arg t "$1" '{hook_event_name:"Stop",session_id:"s1",transcript_path:$t,stop_hook_active:false}' | "$HOOKS" run 2>/dev/null; }
send() { jq -nc --arg t "$1" --arg m "$2" '{hook_event_name:"PreToolUse",tool_name:"SendMessage",session_id:"s1",transcript_path:$t,tool_input:{to:"uds:/x",message:$m}}' | "$HOOKS" run >/dev/null 2>&1; echo $?; }
blocked() { [ -n "$(stop "$2")" ] && ok "blocks: $1" || no "let pass: $1"; }
passes()  { [ -z "$(stop "$2")" ] && ok "passes: $1" || no "blocked: $1 ($(stop "$2" | jq -r .reason | head -1))"; }

printf '\n\033[1mruta\033[0m\n'
"$RUTA" paso batería --min 45 --fuente "corrida r13" >/dev/null
"$RUTA" paso armado --min 11 --fuente "armado-ok de r14" >/dev/null
"$RUTA" paso jueces --min 45 --fuente "juez r14d" --depende armado --necesita "paquete armado" >/dev/null
out=$("$RUTA" hora)
echo "$out" | grep -q "total: 21:56" && ok "critical path: armado then jueces (56 min), battery alongside" || no "critical path wrong: $out"
echo "$out" | grep -q "en serie serían 101" && ok "reports what the serial sum would have been" || no "serial sum missing: $out"
"$RUTA" paso x --min 5 2>/dev/null && no "accepted a step without source" || ok "refuses a step without --fuente"
"$RUTA" paso y --min 5 --fuente f --depende armado 2>/dev/null && no "accepted a dependency without --necesita" || ok "refuses a dependency without the datum it needs"

printf '\n\033[1mB. Ready steps reach the session as context, nothing blocks\033[0m\n'
"$RUTA" paso informe --min 10 --fuente "informe r13" --depende batería --necesita "resultado de la batería" >/dev/null
"$RUTA" paso capturas --min 8 --fuente "capturas r14" >/dev/null
"$RUTA" inicia batería; "$RUTA" inicia armado
f=$(tr r1 "u|ok" "a|20:59|x")
passes "a ready step does not block the end of the turn" "$f"
ctx=$(jq -nc '{hook_event_name:"UserPromptSubmit",session_id:"s1",prompt:"hola",cwd:"/home/kirlts"}' | "$HOOKS" run | jq -r '.hookSpecificOutput.additionalContext // ""')
printf '%s' "$ctx" | grep -q "capturas" && ok "the ready step reaches the session when Martín writes" || no "ready step missing from context: $ctx"
printf '%s' "$ctx" | grep -q "informe" && no "a step waiting on its dependency was listed as ready" || ok "a step whose dependency is running is not listed"
"$RUTA" limite informe 2>/dev/null && no "accepted a limit without a measurement" || ok "refuses a limit without --dato"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
