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

# Text color is derived from the background, so any profile color stays legible.
# A fixed cream foreground was picked for an amber bar and looked wrong on blue.
HOME="$SANDBOX" bash "$ACCOUNT_CMD" mark "$SANDBOX/code/work-project" >/dev/null 2>&1
if grep -q '"titleBar.activeForeground": "#ffffff"' "$marked" 2>/dev/null; then
  ok "dark profile color gets light title text"
else
  no "dark profile color did not get light title text"
fi
cat >"$CONF" <<EOF
profile default $SANDBOX/.claude
profile work    $SANDBOX/.claude-work  *@example.com  #e0f2fe
route   $SANDBOX/code/work-project     work
EOF
rm -f "$marked"
HOME="$SANDBOX" bash "$ACCOUNT_CMD" mark "$SANDBOX/code/work-project" >/dev/null 2>&1
if grep -q '"titleBar.activeForeground": "#111111"' "$marked" 2>/dev/null; then
  ok "light profile color gets dark title text"
else
  no "light profile color did not get dark title text"
fi
cat >"$CONF" <<EOF
profile default $SANDBOX/.claude
profile work    $SANDBOX/.claude-work  *@example.com
route   $SANDBOX/code/work-project     work
EOF
rm -f "$marked"

head_ "Worktrees of a routed repository"
git -C "$SANDBOX/code/work-project" worktree add -q -b wt "$SANDBOX/elsewhere/wt" 2>/dev/null
if [ -d "$SANDBOX/elsewhere/wt" ]; then
  [ "$(route_of "$SANDBOX/elsewhere/wt")" = "$SANDBOX/.claude-work" ] \
    && ok "worktree outside the routed path still uses the profile" \
    || no "worktree outside the routed path lost the profile"
else
  no "could not create a test worktree"
fi

head_ "A route on a subfolder must not claim its whole repository"
# A common use: a narrower, temporary override for one subfolder of a repo that
# already has a route. It must not make the repo's OTHER worktrees, or the repo
# root itself, follow the subfolder's profile instead of the repo's own route.
# Order matters: the router takes the FIRST matching route, so a narrower
# exception has to sit above the broader route it carves out of.
mkdir -p "$SANDBOX/code/work-project/inner"
cat >"$CONF" <<EOF
profile default $SANDBOX/.claude
profile work    $SANDBOX/.claude-work  *@example.com
route   $SANDBOX/code/work-project/inner  default
route   $SANDBOX/code/work-project        work
EOF
[ "$(route_of "$SANDBOX/code/work-project/inner")" = "" ] \
  && ok "the subfolder route itself uses its own profile" \
  || no "the subfolder route did not use its own profile"
[ "$(route_of "$SANDBOX/code/work-project")" = "$SANDBOX/.claude-work" ] \
  && ok "the repository root still uses the repository's route, not the subfolder's" \
  || no "the repository root was hijacked by the subfolder route"
[ "$(route_of "$SANDBOX/elsewhere/wt")" = "$SANDBOX/.claude-work" ] \
  && ok "an existing worktree still follows the repository's own route" \
  || no "an existing worktree was hijacked by the subfolder route"
# Restore the plain config so it does not leak into the tests below.
cat >"$CONF" <<EOF
profile default $SANDBOX/.claude
profile work    $SANDBOX/.claude-work  *@example.com
route   $SANDBOX/code/work-project     work
EOF

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

head_ "Isolating memory and history per profile"
# Shared projects dir, the situation a second profile starts in.
rm -rf "$SANDBOX/.claude/projects" "$SANDBOX/.claude-work/projects"
mkdir -p "$SANDBOX/.claude/projects"
ln -sfn "$SANDBOX/.claude/projects" "$SANDBOX/.claude-work/projects"

# A work project, identified by the cwd inside its session file.
mkdir -p "$SANDBOX/.claude/projects/-work-encoded"
printf '{"type":"user","cwd":"%s"}\n' "$SANDBOX/code/work-project" \
  >"$SANDBOX/.claude/projects/-work-encoded/s1.jsonl"
# A personal project.
mkdir -p "$SANDBOX/.claude/projects/-personal-thing"
printf '{"type":"user","cwd":"%s"}\n' "$SANDBOX/code/personal-app" \
  >"$SANDBOX/.claude/projects/-personal-thing/s2.jsonl"
# History of a deleted worktree: no cwd resolvable, but the encoded origin of a
# routed repo sits inside its own name.
enc="$(printf '%s' "$SANDBOX/code/work-project" | tr '/' '-')"
mkdir -p "$SANDBOX/.claude/projects/-tmp-claude-1000-${enc}-abc-scratchpad-wt"
printf '{"type":"mode"}\n' \
  >"$SANDBOX/.claude/projects/-tmp-claude-1000-${enc}-abc-scratchpad-wt/s3.jsonl"

HOME="$SANDBOX" bash "$ACCOUNT_CMD" isolate --apply >/dev/null 2>&1

[ -f "$SANDBOX/.claude-work/projects/-work-encoded/s1.jsonl" ] \
  && ok "a project resolved by recorded cwd moves to its profile" \
  || no "a project resolved by recorded cwd did not move"

[ -f "$SANDBOX/.claude/projects/-personal-thing/s2.jsonl" ] \
  && ok "a personal project stays in the default profile" \
  || no "a personal project was moved out of the default profile"

[ -f "$SANDBOX/.claude-work/projects/-tmp-claude-1000-${enc}-abc-scratchpad-wt/s3.jsonl" ] \
  && ok "history of a deleted worktree follows its repo's profile" \
  || no "history of a deleted worktree fell to the default profile"

[ -d "$SANDBOX/.claude-work/projects" ] && [ ! -L "$SANDBOX/.claude-work/projects" ] \
  && ok "the shared projects symlink became a real directory" \
  || no "the projects dir is still a symlink, so nothing was really isolated"

out="$(HOME="$SANDBOX" bash "$ACCOUNT_CMD" isolate 2>&1)"
case "$out" in
  *"Nothing to do"*) ok "running it again reports nothing to do" ;;
  *) no "not idempotent: a second run still wants to move something" ;;
esac

# A directory whose owner cannot be determined, no readable cwd and a name that
# matches no route, must be left alone. Guessing "default" would move history
# out of a restricted account into the least restricted one.
mkdir -p "$SANDBOX/.claude-work/projects/-unknown-origin"
printf 'not json\n' >"$SANDBOX/.claude-work/projects/-unknown-origin/x.jsonl"
HOME="$SANDBOX" bash "$ACCOUNT_CMD" isolate --apply >/dev/null 2>&1
[ -f "$SANDBOX/.claude-work/projects/-unknown-origin/x.jsonl" ] \
  && ok "a project of undeterminable origin stays where it is" \
  || no "a project of undeterminable origin was moved on a guess"

# Conflict: the same session recorded on both sides with different content.
# Nothing may be deleted or overwritten, and the wrong-account copy must go.
mkdir -p "$SANDBOX/.claude/projects/-work-encoded"
# Same cwd so it still classifies as work, different bytes so it is a genuine
# conflict. An identical copy is a different case, handled by deleting it.
printf '{"type":"user","cwd":"%s","stub":true}\n' "$SANDBOX/code/work-project" \
  >"$SANDBOX/.claude/projects/-work-encoded/s1.jsonl"
real_before="$(cat "$SANDBOX/.claude-work/projects/-work-encoded/s1.jsonl" 2>/dev/null)"
HOME="$SANDBOX" bash "$ACCOUNT_CMD" isolate --apply >/dev/null 2>&1
real_after="$(cat "$SANDBOX/.claude-work/projects/-work-encoded/s1.jsonl" 2>/dev/null)"
if [ ! -e "$SANDBOX/.claude/projects/-work-encoded/s1.jsonl" ] \
   && [ -f "$SANDBOX/.config/claude-account-router/orphaned/-work-encoded/s1.jsonl" ] \
   && [ "$real_after" = "$real_before" ]; then
  ok "a conflicting copy is quarantined without overwriting the real one"
else
  no "the conflicting copy was mishandled"
fi

head_ "The editor's view of a folder's history"
# The editor process never sees CLAUDE_CONFIG_DIR, so it looks for every
# folder's sessions under the folder's own encoded name in the DEFAULT profile.
# These cases assert that history stays reachable by folder while the bytes stay
# in the account that produced them.

# The same encoding Claude Code applies: every non-alphanumeric character, not
# just slashes. Written out here on purpose, so the test fails if the
# implementation ever loosens it.
slug() { python3 -c 'import re,sys;sys.stdout.write(re.sub(r"[^a-zA-Z0-9]","-",sys.argv[1]))' "$1"; }

work_slug="$(slug "$SANDBOX/code/work-project")"
view="$SANDBOX/.claude/projects/$work_slug"

[ -L "$view" ] && [ "$(readlink -f "$view")" = "$SANDBOX/.claude-work/projects/-work-encoded" ] \
  && ok "isolate links a routed folder's history where the editor looks" \
  || no "the routed folder's history is not reachable from the default profile"

[ -f "$view/s1.jsonl" ] \
  && ok "the session file is readable through the link" \
  || no "the session file is not readable through the link"

# The personal project already lives where the editor looks. A link would be a
# second name for a directory reached directly.
[ ! -L "$SANDBOX/.claude/projects/-personal-thing" ] \
  && ok "a default-profile project gets no link" \
  || no "a default-profile project was turned into a link"

# History of a folder that no longer exists still belongs to its account, but no
# editor window can ask for it by folder, so it gets no name in the way.
[ ! -e "$SANDBOX/.claude/projects/$(slug "$SANDBOX/code/deleted-wt")" ] \
  && ok "history of a deleted folder gets no view link" \
  || no "a link was written for a folder that does not exist"

# Running it again must see the links as links, not as projects to relocate. If
# isolate moved one, it would land inside the profile it points at and then
# point at itself.
out="$(HOME="$SANDBOX" bash "$ACCOUNT_CMD" isolate 2>&1)"
case "$out" in
  *"Nothing to do"*) ok "a second run leaves the view links alone" ;;
  *) no "not idempotent once the view links exist: $(printf '%s' "$out" | tr '\n' ' ')" ;;
esac

# A folder opened for the first time must get its link before it has history,
# so its very first session shows up in the panel.
mkdir -p "$SANDBOX/code/work-project/fresh"
route_of "$SANDBOX/code/work-project/fresh" >/dev/null
fresh_view="$SANDBOX/.claude/projects/$(slug "$SANDBOX/code/work-project/fresh")"
[ -L "$fresh_view" ] \
  && [ "$(readlink "$fresh_view")" = "$SANDBOX/.claude-work/projects/$(slug "$SANDBOX/code/work-project/fresh")" ] \
  && ok "a launch links a folder that has no history yet" \
  || no "a first launch left the folder's history unreachable"

# Deliberately dangling: creating the target would litter each profile with
# empty directories for folders where Claude was opened and never used.
[ ! -e "$SANDBOX/.claude-work/projects/$(slug "$SANDBOX/code/work-project/fresh")" ] \
  && ok "linking does not create an empty project directory" \
  || no "linking created a project directory before Claude wrote anything"

# Routing changed and the folder is back on the default profile: the link must
# go, or the panel would show another account's history. Same rule as the window
# marker, which may not outlive the profile it describes.
CONF_NOROUTE="$CONF_DIR/routes-noroute.conf"
cat >"$CONF_NOROUTE" <<EOF
profile default $SANDBOX/.claude
profile work    $SANDBOX/.claude-work  *@example.com
EOF
(cd "$SANDBOX/code/work-project/fresh" \
   && HOME="$SANDBOX" CLAUDE_ROUTER_CONFIG="$CONF_NOROUTE" CLAUDE_ROUTER_ORIGIN=test \
      "$ROUTER" /bin/true >/dev/null 2>&1)
[ ! -e "$fresh_view" ] \
  && ok "a folder back on the default profile loses its link" \
  || no "a stale link survived a routing change"

# A link a user made by hand points somewhere that is not a profile's project
# directory. It is not ours; it is never repointed and never removed.
foreign="$SANDBOX/.claude/projects/$(slug "$SANDBOX/code/work-project/fresh")"
mkdir -p "$SANDBOX/elsewhere"
ln -s "$SANDBOX/elsewhere" "$foreign"
route_of "$SANDBOX/code/work-project/fresh" >/dev/null
[ "$(readlink -f "$foreign")" = "$SANDBOX/elsewhere" ] \
  && ok "a link that is not ours is left untouched" \
  || no "a hand made link was clobbered"
rm -f "$foreign"

# A REAL directory where the link belongs means history for this folder exists
# in the wrong account too. Resolving that means comparing and quarantining
# files, which is isolate's job under --apply, never a launch's.
mkdir -p "$foreign"
printf '{"type":"mode"}\n' >"$foreign/stray.jsonl"
route_of "$SANDBOX/code/work-project/fresh" >/dev/null
[ -f "$foreign/stray.jsonl" ] && [ ! -L "$foreign" ] \
  && ok "a launch does not touch real history sitting where the link belongs" \
  || no "a launch moved or replaced real history"
rm -rf "$foreign"

# The encoding must match Claude Code's, which dashes every non-alphanumeric
# character. A slash-only version would name the link wrong for any path holding
# a dot or an underscore, and a symlink named with one dash too few points at
# nothing.
got="$(HOME="$SANDBOX" bash -c '. "'"$ROOT"'/lib/common.sh"; car_project_slug "/home/u/.claude/a_b"')"
[ "$got" = "-home-u--claude-a-b" ] \
  && ok "the slug dashes dots and underscores, not only slashes" \
  || no "the slug encoding does not match Claude Code's: got '$got'"


# ── A marker that git already tracks ────────────────────────────────────────
#
# The one case where adding the ignore rule changes nothing: git does not consult
# info/exclude for a file that is in the index. So the marker travels with the repository, and
# any branch that does not carry the file deletes it from disk on checkout. What the user brings
# is «the title bar disappeared», never «git removed a file», and re-marking looks like it worked
# until the next branch switch.
#
# Cost an afternoon on 2026-08-30, in a repository where the marker had been committed since its
# first commit. Renaming the project folder is what surfaced it.
tracked="$SANDBOX/repo-con-marca-rastreada"
mkdir -p "$tracked/.vscode"
git -C "$tracked" init -q
git -C "$tracked" config user.email t@t
git -C "$tracked" config user.name t
printf '{ "workbench.colorCustomizations": { "titleBar.activeBackground": "#0284c7" } }\n' \
  > "$tracked/.vscode/settings.json"
git -C "$tracked" add -A >/dev/null 2>&1
git -C "$tracked" commit -qm "marker committed, as it happened for real" >/dev/null 2>&1

conf="$SANDBOX/rutas-marca.conf"
printf 'profile default ~/.claude\nprofile otra    ~/.claude-otra  alguien@ejemplo.cl  #0284c7\nroute %s otra\n' \
  "$tracked" > "$conf"

CLAUDE_ROUTER_CONFIG="$conf" "$ROOT/bin/claude-account" mark "$tracked" >/dev/null 2>&1

git -C "$tracked" ls-files --error-unmatch .vscode/settings.json >/dev/null 2>&1 \
  && no "mark left the marker tracked by git; a branch switch will delete it" \
  || ok "mark takes a tracked marker out of the index"

[ -s "$tracked/.vscode/settings.json" ] \
  && ok "and leaves it on disk, where the editor reads it" \
  || no "mark removed the marker from disk instead of just untracking it"

grep -q "titleBar.activeBackground" "$tracked/.vscode/settings.json" 2>/dev/null \
  && ok "with its colour intact" \
  || no "the marker lost its colour"

CLAUDE_ROUTER_CONFIG="$conf" "$ROOT/bin/claude-account-check" 2>&1 | grep -q "TRACKED by git" \
  && no "check still reports a tracked marker after mark fixed it" \
  || ok "check stops reporting it once the marker is out of the index"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
