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

printf '\n\033[1mA. Hours\033[0m\n'
f=$(tr h1 "u|cómo va" "a|20:59|Los jueces terminan a las 21:56.")
"$RUTA" inicia batería; "$RUTA" inicia armado
passes "hour equal to the route's finish" "$f"
f=$(tr h2 "u|cómo va" "a|20:59|Los jueces terminan a las 22:41.")
blocked "hour summed in series (battery + armado + judges)" "$f"
f=$(tr h3 "u|despiértame a las 22:41" "a|20:59|Listo, a las 22:41.")
passes "hour Martín typed" "$f"
f=$(tr h4 "u|cómo va" "a|20:59|Empezó a las 20:10 y quedó listo.")
passes "past hours" "$f"
[ "$(send "$f" "Gestión: resultado a las 23:30")" = 2 ] && ok "blocks SendMessage with an hour off the route" || no "SendMessage with an hour off the route passed"
[ "$(send "$f" "Gestión: resultado a las 21:56")" = 0 ] && ok "SendMessage with the route's hour passes" || no "SendMessage with the route's hour blocked"

printf '\n\033[1mB. Ready steps\033[0m\n'
"$RUTA" paso informe --min 10 --fuente "informe r13" --depende batería --necesita "resultado de la batería" >/dev/null
"$RUTA" paso capturas --min 8 --fuente "capturas r14" >/dev/null
f=$(tr r1 "u|ok" "a|20:59|Espero a que termine la batería.")
blocked "an independent step ready and not started" "$f"
"$RUTA" limite capturas --dato "memoria libre 1,2 GB, un agente usa 2,1 GB" >/dev/null
passes "the same step with a measured limit" "$f"
"$RUTA" limite informe --dato "sin número" 2>/dev/null && no "accepted a limit without a measurement" || ok "refuses a limit without a number"
"$RUTA" inicia capturas; passes "step started" "$f"

printf '\n\033[1mC. Management talks to a director\033[0m\n'
G=$(tr g1 "u|cómo va" "a|20:40|Los jueces terminan a las 21:56." "n|monitor event" "a|20:59|Las horas no cambian: los jueces terminan a las 21:56.")
echo "{\"sesiones\":{\"gestion\":{\"transcripcion\":\"$G\"}}}" > "$T/reg/ov.json"
blocked "management, turn from a notification, nothing changed" "$G"
cp "$G" "$T/g1b.jsonl"; G2="$T/g1b.jsonl"
f=$(tr g2 "u|cómo va" "a|20:59|Las horas no cambian: los jueces terminan a las 21:56.")
echo "{\"sesiones\":{\"gestion\":{\"transcripcion\":\"$f\"}}}" > "$T/reg/ov2.json"
passes "management answering Martín's question, even without change" "$f"
f=$(tr g3 "u|cómo va" "n|monitor event" "a|20:59|Quedó publicado: https://ejemplo.cl/prototipo")
echo "{\"sesiones\":{\"gestion\":{\"transcripcion\":\"$f\"}}}" > "$T/reg/ov3.json"
passes "management delivering a link" "$f"
f=$(tr g4 "u|cómo va" "n|monitor event" "a|20:59|¿Lanzo tres jueces o uno?")
echo "{\"sesiones\":{\"gestion\":{\"transcripcion\":\"$f\"}}}" > "$T/reg/ov4.json"
passes "management asking a decision" "$f"
f=$(tr g5 "u|cómo va" "n|monitor event" "a|20:59|Las horas no cambian.")
passes "the same text in a session that is not management" "$f"

f=$(tr g6 "u|cómo va" "n|monitor event" "a|20:58|Las horas no cambian." "u|[Your previous response had no visible output. Please continue and produce a user-visible response." "a|20:59|·")
echo "{\"sesiones\":{\"gestion\":{\"transcripcion\":\"$f\"}}}" > "$T/reg/ov6.json"
passes "management answering «·» after the harness asks for visible output (no loop)" "$f"
f=$(tr g7 "u|cómo va" "n|monitor event" "a|20:58|x" "u|Stop hook feedback: Blocked" "a|20:59|Las horas no cambian.")
echo "{\"sesiones\":{\"gestion\":{\"transcripcion\":\"$f\"}}}" > "$T/reg/ov7.json"
blocked "a continuation after a block is still the notification's turn" "$f"

printf '\n\033[1mSabotage\033[0m\n'
f=$(tr s1 "u|cómo va" "a|20:59|Los jueces terminan a las 22:41.")
[ -z "$(EFICIENCIA_GUARD=0 stop "$f")" ] && ok "with the guard off the serial hour passes (the cases above depend on it)" || no "guard off still blocks"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
