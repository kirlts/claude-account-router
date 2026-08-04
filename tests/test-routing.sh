#!/usr/bin/env bash
# End-to-end tests for the routing and the fail-closed guarantees.
#
#   ./tests/test-routing.sh
#
# Every test runs against a throwaway HOME, so a real installation is never
# touched. Fake credential files contain no tokens, only the identity field the
# router reads.

set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROUTER="$ROOT/bin/claude-account-router"

pass=0; fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; pass=$((pass + 1)); }
no()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# A fake account: identity file plus a non-empty credentials file.
make_account() {  # $1 = config dir, $2 = identity json path, $3 = email
  mkdir -p "$1"
  printf '{"oauthAccount":{"emailAddress":"%s"}}\n' "$3" >"$2"
  printf '{"note":"test placeholder, not a credential"}\n' >"$1/.credentials.json"
}

make_repo() {  # $1 = path
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

# Run the router in a folder; echo the config dir it chose. Exit code 1 means
# the router blocked. `sh -c` always exits 0 so the code reflects only that.
route_of() {  # $1 = folder
  (cd "$1" && HOME="$SANDBOX" CLAUDE_ROUTER_ORIGIN=test \
     "$ROUTER" /bin/sh -c 'printf "%s" "${CLAUDE_CONFIG_DIR-}"' 2>/dev/null)
}

# ── fixture ────────────────────────────────────────────────────────────────
CONF_DIR="$SANDBOX/.config/claude-account-router"
mkdir -p "$CONF_DIR"
CONF="$CONF_DIR/routes.conf"

make_repo "$SANDBOX/code/work-project"
make_repo "$SANDBOX/code/personal-app"
mkdir -p "$SANDBOX/code/plain-folder"

cat >"$CONF" <<EOF
profile default $SANDBOX/.claude
profile work    $SANDBOX/.claude-work  *@example.com
route   $SANDBOX/code/work-project     work
EOF

make_account "$SANDBOX/.claude"      "$SANDBOX/.claude.json"                 "me@personal.test"
make_account "$SANDBOX/.claude-work" "$SANDBOX/.claude-work/.claude.json"    "me@example.com"

head_ "Routing by folder"
[ "$(route_of "$SANDBOX/code/work-project")" = "$SANDBOX/.claude-work" ] \
  && ok "routed folder uses its profile" || no "routed folder did not use its profile"

mkdir -p "$SANDBOX/code/work-project/src"
[ "$(route_of "$SANDBOX/code/work-project/src")" = "$SANDBOX/.claude-work" ] \
  && ok "subfolder of a routed folder inherits the profile" \
  || no "subfolder did not inherit the profile"

# The default profile runs with CLAUDE_CONFIG_DIR unset, which is what Claude
# Code does natively; an empty value is the correct answer here.
[ -z "$(route_of "$SANDBOX/code/personal-app")" ] \
  && ok "unrouted repo falls back to the default profile" \
  || no "unrouted repo did not fall back to the default profile"

[ -z "$(route_of "$SANDBOX/code/plain-folder")" ] \
  && ok "unrouted non-git folder falls back to the default profile" \
  || no "unrouted non-git folder did not fall back"

mkdir -p "$SANDBOX/code/work-project/a/b/c/d"
[ "$(route_of "$SANDBOX/code/work-project/a/b/c/d")" = "$SANDBOX/.claude-work" ] \
  && ok "deeply nested subfolder inherits the profile" \
  || no "deeply nested subfolder did not inherit the profile"

# A folder opened through a symlink keeps PWD as the symlink path, so a literal
# prefix comparison misses it. The canonical comparison is what catches it.
ln -sfn "$SANDBOX/code/work-project" "$SANDBOX/link-to-work"
[ "$(route_of "$SANDBOX/link-to-work")" = "$SANDBOX/.claude-work" ] \
  && ok "folder reached through a symlink still routes to its profile" \
  || no "symlinked path escaped its route"

head_ "Window marker (mark / unmark)"
ACCOUNT_CMD="$ROOT/bin/claude-account"
mkdir -p "$SANDBOX/code/work-project/.vscode"
printf '{\n  "editor.tabSize": 7\n}\n' >"$SANDBOX/code/work-project/.vscode/settings.json"
HOME="$SANDBOX" bash "$ACCOUNT_CMD" mark "$SANDBOX/code/work-project" >/dev/null 2>&1
marked="$SANDBOX/code/work-project/.vscode/settings.json"
if grep -q "titleBar.activeBackground" "$marked" 2>/dev/null; then
  ok "mark writes the title bar color"
else
  no "mark did not write the title bar color"
fi
if grep -q '"editor.tabSize": 7' "$marked" 2>/dev/null; then
  ok "mark preserves settings that were already there"
else
  no "mark clobbered pre-existing settings"
fi
HOME="$SANDBOX" bash "$ACCOUNT_CMD" unmark "$SANDBOX/code/work-project" >/dev/null 2>&1
if ! grep -q "titleBar.activeBackground" "$marked" 2>/dev/null \
   && grep -q '"editor.tabSize": 7' "$marked" 2>/dev/null; then
  ok "unmark removes only the marker keys"
else
  no "unmark removed too much or too little"
fi
HOME="$SANDBOX" bash "$ACCOUNT_CMD" mark "$SANDBOX/code/personal-app" >/dev/null 2>&1
[ $? -ne 0 ] && ok "mark refuses a folder on the default profile" \
             || no "mark accepted a default-profile folder"

head_ "Worktrees of a routed repository"
git -C "$SANDBOX/code/work-project" worktree add -q -b wt "$SANDBOX/elsewhere/wt" 2>/dev/null
if [ -d "$SANDBOX/elsewhere/wt" ]; then
  [ "$(route_of "$SANDBOX/elsewhere/wt")" = "$SANDBOX/.claude-work" ] \
    && ok "worktree outside the routed path still uses the profile" \
    || no "worktree outside the routed path lost the profile"
else
  no "could not create a test worktree"
fi

head_ "Fail closed: wrong account in a routed folder"
printf '{"oauthAccount":{"emailAddress":"intruder@other.test"}}\n' \
  >"$SANDBOX/.claude-work/.claude.json"
route_of "$SANDBOX/code/work-project" >/dev/null 2>&1
[ $? -ne 0 ] && ok "blocked when the profile holds an account outside its glob" \
             || no "did NOT block an account outside the profile glob"
printf '{"oauthAccount":{"emailAddress":"me@example.com"}}\n' \
  >"$SANDBOX/.claude-work/.claude.json"

head_ "Fail closed: leak of a claimed account into the default profile"
printf '{"oauthAccount":{"emailAddress":"me@example.com"}}\n' >"$SANDBOX/.claude.json"
route_of "$SANDBOX/code/personal-app" >/dev/null 2>&1
[ $? -ne 0 ] && ok "blocked when the default profile holds another profile's account" \
             || no "did NOT block the leak into the default profile"
printf '{"oauthAccount":{"emailAddress":"me@personal.test"}}\n' >"$SANDBOX/.claude.json"

head_ "Fail closed: unreadable identity with credentials present"
printf 'not json at all\n' >"$SANDBOX/.claude-work/.claude.json"
route_of "$SANDBOX/code/work-project" >/dev/null 2>&1
[ $? -ne 0 ] && ok "blocked when the account email cannot be read" \
             || no "did NOT block an unreadable identity"
printf '{"oauthAccount":{"emailAddress":"me@example.com"}}\n' \
  >"$SANDBOX/.claude-work/.claude.json"

head_ "Fail closed: missing config dir for a profile"
mv "$SANDBOX/.claude-work" "$SANDBOX/.claude-work-hidden"
route_of "$SANDBOX/code/work-project" >/dev/null 2>&1
[ $? -ne 0 ] && ok "blocked when the profile config dir is gone" \
             || no "did NOT block a missing profile config dir"
mv "$SANDBOX/.claude-work-hidden" "$SANDBOX/.claude-work"

head_ "Fail closed: no config file"
mv "$CONF" "$CONF.away"
route_of "$SANDBOX/code/work-project" >/dev/null 2>&1
[ $? -ne 0 ] && ok "blocked when there is no config file" \
             || no "did NOT block a missing config file"
mv "$CONF.away" "$CONF"

head_ "First login is allowed"
rm -f "$SANDBOX/.claude-work/.credentials.json"
[ "$(route_of "$SANDBOX/code/work-project")" = "$SANDBOX/.claude-work" ] \
  && ok "a profile with no session still starts, so you can log in" \
  || no "a profile with no session was blocked, making the first login impossible"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
