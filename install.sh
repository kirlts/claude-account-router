#!/usr/bin/env bash
# Install claude-account-router by linking its commands into your PATH.
#
#   ./install.sh              install into ~/.local/bin
#   PREFIX=~/bin ./install.sh install somewhere else
#   ./install.sh --uninstall  remove the links
#
# Symlinks, not copies: a git pull updates the installed commands.

set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/claude-account-router"
COMMANDS=(claude-account-router claude-account claude-account-check claude-account-hooks claude-account-relay)

green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[90m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

if [ "${1:-}" = "--uninstall" ]; then
  for c in "${COMMANDS[@]}"; do
    if [ -L "$PREFIX/$c" ]; then rm -f "$PREFIX/$c"; dim "removed $PREFIX/$c"; fi
  done
  green "Uninstalled. Your config and sessions in $CONFIG_HOME were left alone."
  dim "Also remove claudeCode.claudeProcessWrapper from your editor settings."
  exit 0
fi

command -v python3 >/dev/null || { printf 'python3 is required.\n' >&2; exit 1; }
command -v git >/dev/null     || { printf 'git is required.\n' >&2; exit 1; }

mkdir -p "$PREFIX"
for c in "${COMMANDS[@]}"; do
  chmod +x "$ROOT/bin/$c"
  ln -sfn "$ROOT/bin/$c" "$PREFIX/$c"
  dim "linked $PREFIX/$c"
done

mkdir -p "$CONFIG_HOME"
if [ ! -e "$CONFIG_HOME/routes.conf" ]; then
  cp "$ROOT/examples/routes.conf.example" "$CONFIG_HOME/routes.conf"
  green "Created $CONFIG_HOME/routes.conf from the example"
else
  dim "kept existing $CONFIG_HOME/routes.conf"
fi

printf '\n'; green "Installed."
printf '\n'; bold "Next steps"
cat <<EOF
  1. Declare your profiles and routes:
       \$EDITOR $CONFIG_HOME/routes.conf

  2. Point your editor at the router. In VS Code user settings (JSON):
       "claudeCode.claudeProcessWrapper": "$PREFIX/claude-account-router"

  3. Reload the editor window, then verify:
       claude-account-check
EOF

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) printf '\n'; dim "Note: $PREFIX is not in your PATH. Add it to your shell profile." ;;
esac
