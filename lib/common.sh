#!/usr/bin/env bash
# Shared logic for claude-account-router and its companion commands.
#
# Sourced, never executed. Every function here is used by more than one command;
# the identity resolution in particular must exist in exactly one place, because
# getting its path wrong makes the account check pass silently while checking
# nothing.

CAR_VERSION="1.2.0"
CAR_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/claude-account-router"
CAR_CONFIG_FILE="${CLAUDE_ROUTER_CONFIG:-$CAR_CONFIG_HOME/routes.conf}"
CAR_LOG_FILE="${CLAUDE_ROUTER_LOG:-$CAR_CONFIG_HOME/router.log}"
CAR_DEFAULT_PROFILE="default"

declare -A CAR_PROFILE_DIR=()
declare -A CAR_PROFILE_GLOB=()
declare -A CAR_PROFILE_COLOR=()
CAR_ROUTE_PATHS=()
CAR_ROUTE_PROFILES=()

# Default title bar color used by `claude-account mark` when a profile declares
# none. Amber reads as "not your usual window" in both light and dark themes.
CAR_DEFAULT_COLOR="#7c4a03"

car_log() {
  mkdir -p "$(dirname "$CAR_LOG_FILE")" 2>/dev/null || true
  printf '%s %s\n' "$(date -Is)" "$*" >>"$CAR_LOG_FILE" 2>/dev/null || true
}

# Expand a leading ~ and strip any trailing slash.
car_expand_path() {
  local p="$1"
  case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#\~/}" ;; esac
  [ "$p" = "/" ] && { printf '/'; return; }
  printf '%s' "${p%/}"
}

# Populate CAR_PROFILE_* and CAR_ROUTE_*. Returns 1 when the config is missing.
car_load_config() {
  [ -f "$CAR_CONFIG_FILE" ] || return 1
  local kind a b c d
  while read -r kind a b c d || [ -n "$kind" ]; do
    case "$kind" in
      ''|'#'*) continue ;;
      profile)
        [ -n "${a:-}" ] && [ -n "${b:-}" ] || continue
        CAR_PROFILE_DIR["$a"]="$(car_expand_path "$b")"
        CAR_PROFILE_GLOB["$a"]="${c:-}"
        CAR_PROFILE_COLOR["$a"]="${d:-}"
        ;;
      route)
        [ -n "${a:-}" ] && [ -n "${b:-}" ] || continue
        CAR_ROUTE_PATHS+=("$(car_expand_path "$a")")
        CAR_ROUTE_PROFILES+=("$b")
        ;;
      *) car_log "WARN unknown directive '$kind' in $CAR_CONFIG_FILE" ;;
    esac
  done < "$CAR_CONFIG_FILE"
  [ -n "${CAR_PROFILE_DIR[$CAR_DEFAULT_PROFILE]:-}" ] \
    || CAR_PROFILE_DIR["$CAR_DEFAULT_PROFILE"]="$HOME/.claude"
  return 0
}

# Absolute git common dir, so every worktree of a repo resolves to one identity.
car_git_common_dir() {
  local d
  d="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$d" ] || return 1
  readlink -f "$d" 2>/dev/null || printf '%s' "$d"
}

# Is `dir` the top level of its own git working tree, as opposed to a subfolder
# inside a larger repository? A route on a subfolder still routes by path
# prefix, but must NOT claim the whole repository's identity: doing so would
# make every worktree of that repository match the subfolder's route instead
# of the repository's own route, which is backwards from what a narrower,
# more specific route is supposed to mean.
car_is_repo_toplevel() {
  local dir="$1" top
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  [ "$(car_canonical "$dir")" = "$(car_canonical "$top")" ]
}

car_canonical() { readlink -f "$1" 2>/dev/null || printf '%s' "$1"; }

# Is `dir` the route itself, or anywhere below it? Compared both literally and
# canonically, so opening a folder through a symlink still matches its route.
car_dir_under() {
  local dir="$1" route="$2" dir_c route_c probe base
  dir_c="$(car_canonical "$dir")"
  route_c="$(car_canonical "$route")"
  for probe in "$dir" "$dir_c"; do
    for base in "$route" "$route_c"; do
      [ -n "$probe" ] && [ -n "$base" ] || continue
      [ "$probe" = "$base" ] && return 0
      case "$probe" in "$base"/*) return 0 ;; esac
    done
  done
  return 1
}

# Which profile owns a directory. Falls back to the default profile.
#
# Path prefix first, so every subfolder of a routed folder inherits its profile.
# Then repository identity, which catches a worktree living outside the routed
# path entirely.
car_profile_for_dir() {
  local dir="$1" i n common route_common
  n=${#CAR_ROUTE_PATHS[@]}
  for ((i = 0; i < n; i++)); do
    if car_dir_under "$dir" "${CAR_ROUTE_PATHS[$i]}"; then
      printf '%s' "${CAR_ROUTE_PROFILES[$i]}"; return
    fi
  done
  common="$(car_git_common_dir "$dir")" || { printf '%s' "$CAR_DEFAULT_PROFILE"; return; }
  for ((i = 0; i < n; i++)); do
    # Only a route that IS its repository's top level may claim the whole
    # repository's identity for worktree matching. A route on a subfolder
    # inside a larger repo shares that repo's common dir too, which would
    # otherwise make every worktree of the repo match the narrower, more
    # specific route instead of the repo's own route.
    car_is_repo_toplevel "${CAR_ROUTE_PATHS[$i]}" || continue
    route_common="$(car_git_common_dir "${CAR_ROUTE_PATHS[$i]}")" || continue
    if [ "$common" = "$route_common" ]; then printf '%s' "${CAR_ROUTE_PROFILES[$i]}"; return; fi
  done
  printf '%s' "$CAR_DEFAULT_PROFILE"
}

# Email of the account logged into a config dir, empty when there is none.
#
# Claude Code does NOT keep this at <config-dir>/.claude.json. It resolves:
#   1. <config-dir>/.config.json           when that file exists
#   2. ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json
# For the default profile the file therefore lives at $HOME/.claude.json, NOT
# inside ~/.claude. Reading the wrong path returns empty, which makes an identity
# check pass while verifying nothing. This function is the single source of that
# resolution for every command in this project.
car_account_email() {
  local dir="$1" base
  if [ "$dir" = "$HOME/.claude" ]; then base="$HOME"; else base="$dir"; fi
  CAR_CFG_DIR="$dir" CAR_BASE_DIR="$base" python3 - <<'PY' 2>/dev/null
import json, os
d, base = os.environ["CAR_CFG_DIR"], os.environ["CAR_BASE_DIR"]
for cand in (os.path.join(d, ".config.json"), os.path.join(base, ".claude.json")):
    if not os.path.exists(cand):
        continue
    try:
        with open(cand) as f:
            print((json.load(f).get("oauthAccount") or {}).get("emailAddress") or "")
    except Exception:
        pass
    break
PY
}

# Path of the json file that holds the account identity for a config dir.
car_identity_file() {
  local dir="$1"
  if [ -f "$dir/.config.json" ]; then printf '%s' "$dir/.config.json"; return; fi
  if [ "$dir" = "$HOME/.claude" ]; then printf '%s' "$HOME/.claude.json"
  else printf '%s' "$dir/.claude.json"; fi
}

car_has_session() { [ -s "$1/.credentials.json" ]; }

# Write, update, or remove the window marker of a folder.
#
# One implementation for both callers, because they must agree on every byte:
#   mode=create  `claude-account mark`. Creates or merges into the file.
#   mode=sync    the router, on every launch. Only ever updates a marker that
#                already exists, and removes it when the folder now resolves to
#                the default profile.
#
# Why the router syncs at all: `mark` writes a static file. If routing later
# changes for that folder, for example a narrower route exception, the color
# stays behind describing the OLD profile while Claude launches under the NEW
# one. That is the same class of mismatch this project exists to prevent, moved
# from the account to the indicator claiming an account. Since the router only
# reaches this point after the identity check passed, the profile it resolved
# and the live account are the same thing, so syncing the marker against the
# profile is syncing it against the account.
#
# It only ever touches a file carrying this project's marker signature: a
# window.title starting with "[" plus at least one of our four color keys. A
# hand made title bar customization is never clobbered.
#
# Text colors are derived from the background rather than fixed, so any profile
# color stays legible. A fixed cream foreground was chosen for an amber bar and
# looked dirty on a blue one.
car_write_marker() {  # $1 = dir, $2 = profile name, $3 = create|sync
  local dir="$1" profile="$2" mode="$3" f label color
  f="$dir/.vscode/settings.json"

  [ "$mode" = "sync" ] && [ ! -f "$f" ] && return 0

  if [ "$profile" = "$CAR_DEFAULT_PROFILE" ]; then
    label=""; color=""
  else
    label="$(printf '%s' "$profile" | tr '[:lower:]' '[:upper:]')"
    color="${CAR_PROFILE_COLOR[$profile]:-$CAR_DEFAULT_COLOR}"
    [ "$mode" = "create" ] && mkdir -p "$dir/.vscode"
  fi

  CAR_FILE="$f" CAR_LABEL="$label" CAR_COLOR="$color" CAR_MODE="$mode" python3 - <<'PY'
import json, os, re, sys

path = os.environ["CAR_FILE"]
label, color, mode = os.environ["CAR_LABEL"], os.environ["CAR_COLOR"], os.environ["CAR_MODE"]
quiet = mode == "sync"
MARKER_KEYS = ("titleBar.activeBackground", "titleBar.activeForeground",
               "titleBar.inactiveBackground", "titleBar.inactiveForeground")

def bail(msg="", code=0):
    if msg and not quiet:
        print(msg, file=sys.stderr)
    raise SystemExit(code)

def channels(hexcolor):
    h = hexcolor.lstrip("#")
    if len(h) != 6:
        return None
    try:
        return [int(h[i:i+2], 16) for i in (0, 2, 4)]
    except ValueError:
        return None

def to_hex(ch):
    return "#" + "".join("%02x" % max(0, min(255, int(round(c)))) for c in ch)

def luminance(ch):
    # Relative luminance, sRGB, per WCAG.
    def lin(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in ch)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def scale(ch, factor):
    return [c * factor for c in ch]

def mix(a, b, t):
    return [a[i] * t + b[i] * (1 - t) for i in range(3)]

def marker_colors(color):
    ch = channels(color)
    if ch is None:
        return None
    fg = [255, 255, 255] if luminance(ch) < 0.45 else [17, 17, 17]
    inactive_bg = scale(ch, 0.6)
    return {
        "titleBar.activeBackground": to_hex(ch),
        "titleBar.activeForeground": to_hex(fg),
        "titleBar.inactiveBackground": to_hex(inactive_bg),
        # Attenuated toward its own bar instead of a fixed beige, so it reads as
        # the same color family at any hue.
        "titleBar.inactiveForeground": to_hex(mix(fg, inactive_bg, 0.62)),
    }

data, existed = {}, os.path.exists(path)
if existed:
    try:
        data = json.loads(re.sub(r'^\s*//.*$', '', open(path).read(), flags=re.M) or "{}")
    except Exception:
        bail("Existing .vscode/settings.json is not parseable; leaving it alone.\n"
             "Fix the file and rerun, or add the marker by hand.", 1)
    if not isinstance(data, dict):
        bail("Existing .vscode/settings.json is not an object; leaving it alone.", 1)

title = data.get("window.title", "")
colors = data.get("workbench.colorCustomizations")
is_ours = (isinstance(title, str) and title.startswith("[")
           and isinstance(colors, dict) and any(k in colors for k in MARKER_KEYS))

if mode == "sync" and not is_ours:
    bail()  # not our marker, or no marker at all

if not isinstance(colors, dict):
    colors = {}

if not label:
    # Folder now resolves to the default profile: a marker has no business
    # surviving on a folder that is not, at this moment, another account.
    if mode == "create":
        bail("This folder routes to the default profile, so there is nothing to mark.", 1)
    for k in MARKER_KEYS:
        colors.pop(k, None)
    if colors:
        data["workbench.colorCustomizations"] = colors
    else:
        data.pop("workbench.colorCustomizations", None)
    data.pop("window.title", None)
else:
    wanted = marker_colors(color)
    if wanted is None:
        bail("Profile color %r is not a 6 digit hex value." % color, 1)
    new_title = "[%s] ${rootName}${separator}${activeEditorShort}" % label
    if mode == "sync" and title == new_title and all(
            colors.get(k) == v for k, v in wanted.items()):
        bail()  # already correct, do not rewrite for nothing
    data["window.title"] = new_title
    colors.update(wanted)
    data["workbench.colorCustomizations"] = colors

if data:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    if not quiet:
        print("updated" if existed else "created")
elif os.path.exists(path):
    os.remove(path)
    if not quiet:
        print("file removed (it held only the marker)")
PY
}

# Kept as the router's entry point, so the call site reads as intent.
car_sync_marker() { car_write_marker "$1" "$2" sync; }

# Glob match usable inside a conditional, no subshell.
car_glob_match() {
  local value="$1" pattern="$2"
  # shellcheck disable=SC2254
  case "$value" in $pattern) return 0 ;; *) return 1 ;; esac
}

# Every declared profile name, default first, then the rest sorted.
car_profile_names() {
  local p
  printf '%s\n' "$CAR_DEFAULT_PROFILE"
  for p in "${!CAR_PROFILE_DIR[@]}"; do
    [ "$p" = "$CAR_DEFAULT_PROFILE" ] || printf '%s\n' "$p"
  done | sort
}
