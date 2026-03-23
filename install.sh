#!/usr/bin/env bash
# install.sh — claude-obsidian-logger のセットアップ / アンインストール
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGGER_SCRIPT="$SCRIPT_DIR/claude-obsidian-log.sh"
SYMLINK_DIR="$HOME/.local/bin"
SYMLINK="$SYMLINK_DIR/claude-obsidian-log.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger"
CONFIG_FILE="$CONFIG_DIR/config"
SETTINGS="$HOME/.claude/settings.json"
MATCHER="Edit|Write|MultiEdit|Bash"

# --- アンインストール ---
if [ "${1:-}" = "--uninstall" ]; then
  echo "Uninstalling claude-obsidian-logger..."

  if [ -L "$SYMLINK" ]; then
    rm "$SYMLINK"
    echo "  Removed symlink: $SYMLINK"
  fi

  if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    tmp="$(mktemp)"
    jq --arg m "$MATCHER" \
      'del(.hooks.PostToolUse[]? | select(.matcher == $m))' \
      "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  Removed hook from: $SETTINGS"
  fi

  echo "Done. Config file retained at: $CONFIG_FILE"
  exit 0
fi

# --- インストール ---
echo "Installing claude-obsidian-logger..."

# jq チェック
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it first:" >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Ubuntu: sudo apt install jq" >&2
  exit 1
fi

# 設定ファイル作成
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
# claude-obsidian-logger configuration
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"
LOG_DIR="Claude Code"
EOF
  echo "  Created config: $CONFIG_FILE"
else
  echo "  Config already exists: $CONFIG_FILE (skipped)"
fi

# シンボリックリンク作成
mkdir -p "$SYMLINK_DIR"
if [ -L "$SYMLINK" ]; then
  rm "$SYMLINK"
fi
ln -s "$LOGGER_SCRIPT" "$SYMLINK"
echo "  Created symlink: $SYMLINK -> $LOGGER_SCRIPT"

# PATH 案内
if ! echo "$PATH" | grep -q "$SYMLINK_DIR"; then
  echo "  Note: Add $SYMLINK_DIR to your PATH:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# settings.json に hook 追加（冪等）
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

already="$(jq --arg m "$MATCHER" \
  '[.hooks.PostToolUse[]? | select(.matcher == $m)] | length' \
  "$SETTINGS" 2>/dev/null || echo 0)"

if [ "$already" -gt 0 ]; then
  echo "  Hook already registered in: $SETTINGS (skipped)"
else
  tmp="$(mktemp)"
  jq --arg m "$MATCHER" --arg cmd "$SYMLINK" '
    .hooks.PostToolUse = (
      (.hooks.PostToolUse // []) +
      [{"matcher": $m, "hooks": [{"type": "command", "command": $cmd}]}]
    )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  Added hook to: $SETTINGS"
fi

echo ""
echo "Done! claude-obsidian-logger is installed."
echo "Edit config to set your vault path: $CONFIG_FILE"
