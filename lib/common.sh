#!/usr/bin/env bash
# Shared logic for claude-account-router and its companion commands.
#
# Sourced, never executed. Every function here is used by more than one command;
# the identity resolution in particular must exist in exactly one place, because
# getting its path wrong makes the account check pass silently while checking
# nothing.

CAR_VERSION="1.0.0"
CAR_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/claude-account-router"
CAR_CONFIG_FILE="${CLAUDE_ROUTER_CONFIG:-$CAR_CONFIG_HOME/routes.conf}"
CAR_LOG_FILE="${CLAUDE_ROUTER_LOG:-$CAR_CONFIG_HOME/router.log}"
CAR_DEFAULT_PROFILE="default"

declare -A CAR_PROFILE_DIR=()
declare -A CAR_PROFILE_GLOB=()
CAR_ROUTE_PATHS=()
CAR_ROUTE_PROFILES=()

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
  local kind a b c
  while read -r kind a b c || [ -n "$kind" ]; do
    case "$kind" in
      ''|'#'*) continue ;;
      profile)
        [ -n "${a:-}" ] && [ -n "${b:-}" ] || continue
        CAR_PROFILE_DIR["$a"]="$(car_expand_path "$b")"
        CAR_PROFILE_GLOB["$a"]="${c:-}"
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

# Which profile owns a directory. Falls back to the default profile.
car_profile_for_dir() {
  local dir="$1" i n route common route_common
  n=${#CAR_ROUTE_PATHS[@]}
  for ((i = 0; i < n; i++)); do
    route="${CAR_ROUTE_PATHS[$i]}"
    if [ "$dir" = "$route" ]; then printf '%s' "${CAR_ROUTE_PROFILES[$i]}"; return; fi
    case "$dir" in "$route"/*) printf '%s' "${CAR_ROUTE_PROFILES[$i]}"; return ;; esac
  done
  common="$(car_git_common_dir "$dir")" || { printf '%s' "$CAR_DEFAULT_PROFILE"; return; }
  for ((i = 0; i < n; i++)); do
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
