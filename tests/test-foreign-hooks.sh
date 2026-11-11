#!/usr/bin/env bash
# Tests for claude-account-hooks: a declared repository's hooks run for a session opened elsewhere.
#
#   ./tests/test-foreign-hooks.sh
#
# Runs against a throwaway HOME, so a real installation is never touched.

set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HOOKS="${HOOKS_BIN:-$ROOT/bin/claude-account-hooks}"

pass=0; fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/home/.config" XDG_STATE_HOME="$SANDBOX/home/.local/state"
mkdir -p "$HOME/.config/claude-account-router" "$HOME/profile-a" "$HOME/profile-b"

make_repo() {  # $1 = path; hooks: Edit|Write blocks FORBIDDEN, prompt and tool calls add context
  mkdir -p "$1/.claude"
  git -C "$1" init -q
  cat >"$1/.claude/block.sh" <<'EOF'
#!/bin/bash
grep -q FORBIDDEN && { echo "blocked by $CLAUDE_PROJECT_DIR" >&2; exit 2; }
exit 0
EOF
  cat >"$1/.claude/remind.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
printf '{"hookSpecificOutput":{"hookEventName":"x","additionalContext":"REMINDER from %s"}}' "$(basename "$CLAUDE_PROJECT_DIR")"
EOF
  chmod +x "$1/.claude/block.sh" "$1/.claude/remind.sh"
  cat >"$1/.claude/settings.json" <<'EOF'
{"hooks":{
  "PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/block.sh"}]}],
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/remind.sh"}]}]
}}
EOF
}

OWN="$HOME/own"; FOREIGN="$HOME/foreign"; UNDECLARED="$HOME/undeclared"
make_repo "$OWN"; make_repo "$FOREIGN"; make_repo "$UNDECLARED"
cat >"$HOME/.config/claude-account-router/routes.conf" <<EOF
profile a $HOME/profile-a
profile b $HOME/profile-b
route $OWN a
route $FOREIGN b
EOF

hook() {  # $1 = project dir, $2 = event json; prints stdout, sets RC
  OUT=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" "$HOOKS" run 2>"$SANDBOX/err"); RC=$?
}
write_event() {  # $1 = session, $2 = file, $3 = content, [$4 = cwd, default the own repository]
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$1" "${4:-$OWN}" "$2" "$3"
}
prompt_event() { printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","cwd":"%s","prompt":"hi"}' "$1" "$OWN"; }

printf '\n\033[1mforeign hooks\033[0m\n'

hook "$OWN" "$(write_event s1 "$FOREIGN/src/a.js" FORBIDDEN)"
[ "$RC" = 2 ] && grep -q "blocked by $FOREIGN" "$SANDBOX/err" && ok "a forbidden edit in a declared repository is blocked by its own hook" || no "forbidden edit not blocked (rc=$RC)"

hook "$OWN" "$(write_event s2 "$FOREIGN/src/a.js" fine)"
[ "$RC" = 0 ] && ok "an allowed edit in the declared repository passes" || no "allowed edit rc=$RC"

hook "$OWN" "$(prompt_event s3)"
[ -z "$OUT" ] && ok "a session that never touched the repository gets none of its hooks" || no "untouched session got: $OUT"

hook "$OWN" "$(prompt_event s2)"
printf '%s' "$OUT" | grep -q "REMINDER from foreign" && ok "after writing there, the session's prompts run that repository's hooks" || no "marked session prompt got: $OUT"

hook "$OWN" "$(printf '{"hook_event_name":"PreToolUse","session_id":"s4","cwd":"%s","tool_name":"Bash","tool_input":{"command":"grep -r x %s/src"}}' "$OWN" "$FOREIGN")"
hook "$OWN" "$(prompt_event s4)"
[ -z "$OUT" ] && ok "reading a file there does not mark the session" || no "a read marked the session: $OUT"

bash_event() {  # $1 = session, $2 = command line (JSON-escaped by python), cwd = the own repository
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","session_id":sys.argv[1],"cwd":sys.argv[3],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" "$OWN"
}
marks() {  # $1 = session, $2 = command line: 0 when that Bash call marked the session as working in FOREIGN
  hook "$OWN" "$(bash_event "$1" "$2")"
  hook "$OWN" "$(prompt_event "$1")"
  printf '%s' "$OUT" | grep -q "REMINDER from foreign"
}
F="$FOREIGN"
marks s5 "cd $F && touch x" && ok "a cd into the repository followed by a command that writes marks the session" || no "cd + touch did not mark"
marks r1 "cd $F && git status" && no "cd + git status marked the session" || ok "a cd into the repository followed by git status does not mark"
marks r2 "cd $F && cat src/a.js; echo ===; grep -rn x . | head -40; sed -n 1,5p src/a.js" && no "cd + cat/grep/sed -n marked" || ok "a cd followed by cat, grep, sed -n, pipes and echo does not mark"
marks r3 "cd $F; R=origin/main; for c in a b; do echo == \$c; git show \$R:x | grep -i y; git branch -a --contains \$c 2>/dev/null | head -2; done" && no "read-only loop marked" || ok "a read-only loop with variables and git branch --contains does not mark"
marks r4 "cd $F && git fetch -q origin main && git log -1 origin/main && echo \$(git rev-parse HEAD)" && no "fetch/log/\$() marked" || ok "git fetch, git log and a read-only \$() do not mark"
marks r5 "cd $F && find . -name '*.js' | xargs wc -l" && ok "an unrecognized command (xargs) marks: unknown counts as writing" || no "unrecognized command did not mark"
marks r6 "cd $F && echo hi > out.txt" && ok "a cd followed by a write redirection marks" || no "redirect did not mark"
marks r7 "cd $F && echo 'a > b' && cat x" && no "a > inside quotes counted as a redirection" || ok "a > inside quotes is not a redirection"
marks r8 "cd $F && sed -i s/a/b/ src/a.js" && ok "sed -i marks" || no "sed -i did not mark"
marks r9 "cd $F && find . -name x -delete" && ok "find -delete marks" || no "find -delete did not mark"
marks r10 "cd $F && git branch newbranch" && ok "git branch <name> marks" || no "git branch newbranch did not mark"
marks r11 "cat >> /tmp/n.md <<'EOF'
copy the pattern: cd $F && see it
EOF" && no "a cd quoted inside a heredoc marked" || ok "a cd inside a heredoc body is text, not a cd"
marks r12 "cd $F && git status && npm install" && ok "a chain whose last command writes marks" || no "chain with a write did not mark"

hook "$OWN" "$(printf '{"hook_event_name":"PreToolUse","session_id":"s9","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git -C %s show HEAD:x"}}' "$OWN" "$FOREIGN")"
hook "$OWN" "$(prompt_event s9)"
[ -z "$OUT" ] && ok "a read-only git -C into the repository does not mark the session" || no "read-only git -C marked: $OUT"

hook "$OWN" "$(printf '{"hook_event_name":"PreToolUse","session_id":"s9b","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git -C %s log --oneline -5"}}' "$OWN" "$FOREIGN")"
hook "$OWN" "$(prompt_event s9b)"
[ -z "$OUT" ] && ok "git -C log into the repository does not mark the session" || no "read-only git -C log marked: $OUT"

hook "$OWN" "$(printf '{"hook_event_name":"PreToolUse","session_id":"s10","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git -C %s commit -am x"}}' "$OWN" "$FOREIGN")"
hook "$OWN" "$(prompt_event s10)"
printf '%s' "$OUT" | grep -q "REMINDER from foreign" && ok "a write git -C into the repository (commit) marks the session" || no "write git -C did not mark: $OUT"

hook "$OWN" "$(printf '{"hook_event_name":"PreToolUse","session_id":"s11","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git -C %s checkout main"}}' "$OWN" "$FOREIGN")"
hook "$OWN" "$(prompt_event s11)"
printf '%s' "$OUT" | grep -q "REMINDER from foreign" && ok "a write git -C into the repository (checkout) marks the session" || no "write git -C checkout did not mark: $OUT"

hook "$FOREIGN" "$(write_event s6 "$FOREIGN/src/a.js" FORBIDDEN "$FOREIGN")"
[ "$RC" = 0 ] && ok "nothing is run twice when the session was opened in that repository" || no "own repository ran again (rc=$RC)"

hook "$OWN" "$(write_event s7 "$UNDECLARED/src/a.js" FORBIDDEN)"
[ "$RC" = 0 ] && ok "an undeclared repository's hooks are never executed" || no "undeclared repository ran (rc=$RC)"

mkdir -p "$FOREIGN/.claude/worktrees/w/src"
hook "$OWN" "$(write_event s8 "$FOREIGN/.claude/worktrees/w/src/a.js" FORBIDDEN)"
[ "$RC" = 2 ] && ok "a worktree inside the repository gets the repository's hooks" || no "worktree not covered (rc=$RC)"

printf '{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"/old/hook.sh"}]}]},"model":"x"}' >"$HOME/profile-a/settings.json"
"$HOOKS" install --replace /old/hook.sh >/dev/null
"$HOOKS" install >"$SANDBOX/second"
"$HOOKS" check >/dev/null && ok "install registers in every profile" || no "check fails after install"
grep -q "already registered" "$SANDBOX/second" && ok "install is idempotent" || no "second install changed something"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); c=[h["command"] for g in d["hooks"]["PreToolUse"] for h in g["hooks"]]; sys.exit(0 if "/old/hook.sh" not in c and d["model"]=="x" else 1)' "$HOME/profile-a/settings.json" \
  && ok "--replace removes the old entry and keeps the rest of the settings" || no "--replace left the old entry or lost settings"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
