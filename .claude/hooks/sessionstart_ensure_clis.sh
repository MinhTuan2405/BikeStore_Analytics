#!/usr/bin/env bash
# SessionStart hook: ensure CLIs required by enabled plugins are installed.
# Maps plugin → required CLI → install command. Idempotent: only installs when missing.
# Verbose install output goes to LOG_FILE; only short status appears in session.

set -u
SETTINGS="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/settings.json"
LOG_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/ensure_clis.log"
[[ -f "$SETTINGS" ]] || exit 0

is_enabled() {
  python3 -c "
import json
try:
    d = json.load(open('$SETTINGS'))
    print('1' if d.get('enabledPlugins', {}).get('$1') is True else '0')
except Exception:
    print('0')
"
}

ensure_cli() {
  local plugin="$1" cli="$2" install_cmd="$3" homepage="$4"
  [[ "$(is_enabled "$plugin")" == "1" ]] || return 0
  command -v "$cli" >/dev/null 2>&1 && return 0
  # PATH may not yet include ~/.local/bin in a fresh shell
  [[ -x "$HOME/.local/bin/$cli" ]] && return 0

  echo "[hook] Installing missing CLI '$cli' for plugin '$plugin'... (log: $LOG_FILE)" >&2
  {
    echo "=== $(date -Iseconds) installing $cli for $plugin ==="
    eval "$install_cmd"
    echo "=== exit=$? ==="
  } >> "$LOG_FILE" 2>&1

  if command -v "$cli" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/$cli" ]]; then
    echo "[hook] ✓ $cli installed." >&2
  else
    echo "[hook] ✗ Install failed. See $LOG_FILE or install manually: $homepage" >&2
  fi
}

# Plugin → CLI registry
ensure_cli \
  "snowflake-cortex-code@claude-plugins-official" \
  "cortex" \
  "curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh" \
  "https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli"

# Add more here as new plugins are enabled:
# ensure_cli "atlan@claude-plugins-official" "atlan" "..." "..."

exit 0
