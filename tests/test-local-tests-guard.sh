#!/usr/bin/env bash
# Tests for the local tests guard: test runs of a repository with a cloud path are refused here.
#
#   ./tests/test-local-tests-guard.sh
#
# Nothing here runs a test. Each case hands the hook an event as text and reads its verdict.

set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HOOKS="$ROOT/bin/claude-account-hooks"
pass=0; fail=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }
D="$HOME/devalis"

verdict() {  # $1 = cwd, $2 = command
  python3 - "$1" "$2" <<'PY' | "$HOOKS" run >/dev/null 2>&1
import json, sys
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": sys.argv[1],
                  "tool_input": {"command": sys.argv[2]}, "session_id": "t-local-tests"}))
PY
  echo $?
}
refused() { [ "$(verdict "$2" "$3")" = 2 ] && ok "refused: $1" || no "was allowed: $1 ($3)"; }
allowed() { [ "$(verdict "$2" "$3")" = 0 ] && ok "allowed: $1" || no "was refused: $1 ($3)"; }

printf '\n\033[1mRefused\033[0m\n'
refused "npm test inside the repository"        "$D/plataforma"            "npm test"
refused "npm run test:fit"                      "$D/plataforma"            "npm run test:fit -- --grep x"
refused "cd into a worktree, then node --test"  "$HOME/kb-okos"            "cd $D/.claude/worktrees/x/plataforma && node --test src/a.test.js"
refused "node on a test file by absolute path"  "$HOME"                    "node $D/plataforma/src/a.test.js"
refused "wrapped in systemd-run"                "$D/plataforma"            "systemd-run --user --scope -p CPUQuota=600% -p MemoryMax=8G npm test"
refused "npx vitest"                            "$D/plataforma/panel"      "npx vitest run src/x.test.ts"
refused "npx playwright test"                   "$D/plataforma/panel"      "npx playwright test e2e/a.spec.ts"
refused "a docker stack running a command"      "$D/plataforma"            "node scripts/pila-propia.mjs --correr npm test"
refused "npm --prefix into the repository"      "$HOME"                    "npm --prefix $D/plataforma test"
refused "env assignment before the runner"      "$D/plataforma"            "DEVALIS_TANDAS_EN_SERIE=1 npm test"

printf '\n\033[1mAllowed\033[0m\n'
allowed "the cloud path itself"                 "$D"                       "infra/servidor-de-despliegue/probar.sh wt-x"
allowed "a test run on a cloud machine over ssh" "$D"                      "gcloud compute ssh m --command 'cd /x && npm test'"
allowed "plain ssh with a test inside quotes"   "$D"                       "ssh m 'npm test && node --test a.test.js'"
allowed "syntax check"                          "$D/plataforma"            "node --check src/a.js"
allowed "syntax check of a test file"           "$D/plataforma"            "node --check src/a.test.js && echo ok"
allowed "build"                                 "$D/plataforma"            "npm run build"
allowed "typecheck"                             "$D/plataforma"            "npx tsc --noEmit"
allowed "a script that is not a test"           "$D/plataforma"            "node scripts/grabar.mjs"
allowed "tests of a repository with no cloud path" "$HOME/kb-okos"        "python3 tools/test_kb_paralelo.py"
allowed "npm test outside guarded repositories" "$HOME/conversio-connect" "npm test"
allowed "grep for the word test"                "$D"                       "grep -rn 'npm test' docs | head"

printf '\n%d ok, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
