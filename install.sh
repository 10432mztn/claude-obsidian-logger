#!/usr/bin/env bash
# install.sh — claude-obsidian-logger のセットアップ / アンインストール
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMLINK_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger"
CONFIG_FILE="$CONFIG_DIR/config"
SETTINGS="$HOME/.claude/settings.json"
POST_TOOL_MATCHER="Edit|Write|MultiEdit|Bash"

# スクリプト名 → hook イベント の対応
declare -a HOOKS=(
  "claude-obsidian-log.sh:PostToolUse:$POST_TOOL_MATCHER"
  "claude-obsidian-prompt.sh:UserPromptSubmit:"
  "claude-obsidian-session-summary.sh:Stop:"
  "claude-obsidian-daily-rollup.sh:Stop:"
)

# --- アンインストール ---
if [ "${1:-}" = "--uninstall" ]; then
  echo "Uninstalling claude-obsidian-logger..."

  for entry in "${HOOKS[@]}"; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    event="${rest%%:*}"
    symlink="$SYMLINK_DIR/$name"

    if [ -L "$symlink" ]; then
      rm "$symlink"
      echo "  Removed symlink: $symlink"
    fi

    if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
      tmp="$(mktemp)"
      jq --arg cmd "$symlink" --arg ev "$event" \
        "del(.hooks[\$ev][]?.hooks[]? | select(.command | test(\$cmd)))" \
        "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    fi
  done

  echo "  Cleaned hooks from: $SETTINGS"
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
# 環境変数で上書き可能（settings.json の hook command に env を渡すなど）
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"
LOG_DIR="Claude Code"
# Bash コマンドのうち、以下の正規表現に該当する読み取り系コマンドは記録しない
SKIP_BASH_PATTERN="^(ls|cat|head|tail|pwd|which|file|stat|find|echo|printf|grep |/bin/ls|wc |type |whoami|env$|env |sleep )"
EOF
  echo "  Created config: $CONFIG_FILE"
else
  echo "  Config already exists: $CONFIG_FILE (skipped)"
fi

# シンボリックリンク作成
mkdir -p "$SYMLINK_DIR"
for entry in "${HOOKS[@]}"; do
  name="${entry%%:*}"
  target="$SCRIPT_DIR/$name"
  symlink="$SYMLINK_DIR/$name"

  if [ ! -f "$target" ]; then
    echo "  Warning: $target not found, skipping symlink"
    continue
  fi

  if [ -L "$symlink" ]; then
    rm "$symlink"
  fi
  ln -s "$target" "$symlink"
  echo "  Created symlink: $symlink"
done

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

add_hook() {
  local event="$1" matcher="$2" cmd="$3"
  local already
  already="$(jq --arg ev "$event" --arg cmd "$cmd" \
    '[.hooks[$ev][]?.hooks[]? | select(.command == $cmd)] | length' \
    "$SETTINGS" 2>/dev/null || echo 0)"

  if [ "$already" -gt 0 ]; then
    echo "  Hook already registered: $event -> $(basename "$cmd")"
    return
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg ev "$event" --arg m "$matcher" --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks[$ev] = (
      (.hooks[$ev] // []) +
      [{"matcher": $m, "hooks": [{"type": "command", "command": $cmd}]}]
    )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  Added hook: $event -> $(basename "$cmd")"
}

for entry in "${HOOKS[@]}"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  event="${rest%%:*}"
  matcher="${rest#*:}"
  symlink="$SYMLINK_DIR/$name"

  [ -L "$symlink" ] || continue
  add_hook "$event" "$matcher" "$symlink"
done

echo ""
echo "Done! claude-obsidian-logger is installed."
echo "  Config: $CONFIG_FILE"
echo "  Hooks registered: PostToolUse / UserPromptSubmit / Stop x2"
echo ""
echo "Note: Session summaries and daily rollups use the \`claude\` CLI."
echo "      Ensure you are logged in (\`claude\` once interactively) for them to work."
