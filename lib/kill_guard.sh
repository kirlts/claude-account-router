# Source from ~/.bashrc. Replaces the `kill` builtin with a function that asks kill_guard.py
# first. Claude Code builds its shell snapshot from the user's shell, so the function reaches
# every Bash tool call. Refuses when the guard is missing or fails: it fails closed.
__car_kill_guard="@ROOT@/lib/kill_guard.py"
kill() {
  case "${1:-}" in -l|-L|--list|--table) builtin kill "$@"; return ;; esac
  if [ ! -r "$__car_kill_guard" ]; then
    printf 'kill: refused, the guard %s is missing.\n' "$__car_kill_guard" >&2; return 1
  fi
  python3 -I "$__car_kill_guard" kill "$@" || return 1
  builtin kill "$@"
}
