#!/usr/bin/env bash
# install.sh — claude-obsidian-logger のセットアップ / アンインストール
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMLINK_DIR="$HOME/.local/bin"
COMMANDS_DIR="$HOME/.claude/commands"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger"
CONFIG_FILE="$CONFIG_DIR/config"
SETTINGS="$HOME/.claude/settings.json"
POST_TOOL_MATCHER="Edit|Write|MultiEdit|Bash"

# スクリプト名 → hook イベント の対応
declare -a HOOKS=(
  "claude-obsidian-log.sh:PostToolUse:$POST_TOOL_MATCHER"
  "claude-obsidian-prompt.sh:UserPromptSubmit:"
  "claude-obsidian-session-summary.sh:Stop:"
)

# 同梱する slash command（commands/ 配下のファイル名を列挙）
declare -a COMMANDS=(
  "daily-rollup.md"
  "sync-memory.md"
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
      # basename を含む command を持つ hook を削除（env-prefix / 別パス展開でも検出できる）
      jq --arg name "$name" --arg ev "$event" '
        .hooks[$ev] = ([.hooks[$ev][]? |
          .hooks = [.hooks[]? | select((.command | type == "string" and contains($name)) | not)]
        ] | map(select(.hooks | length > 0)))
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    fi
  done

  for cmd_name in "${COMMANDS[@]}"; do
    cmd_link="$COMMANDS_DIR/$cmd_name"
    if [ -L "$cmd_link" ]; then
      rm "$cmd_link"
      echo "  Removed command symlink: $cmd_link"
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
  local script_name
  script_name="$(basename "$cmd")"
  local already
  # スクリプト名（basename）が含まれていれば登録済みとみなす。
  # 既存 hook が env-prefix 付き（例: `OBSIDIAN_VAULT_PATH=... /path/to/script.sh`）でも
  # シンボリックリンク経由（symlink path != source path）でも検出できるよう substring match を使う。
  already="$(jq --arg ev "$event" --arg name "$script_name" \
    '[.hooks[$ev][]?.hooks[]? | select(.command | type == "string" and contains($name))] | length' \
    "$SETTINGS" 2>/dev/null || echo 0)"

  if [ "$already" -gt 0 ]; then
    echo "  Hook already registered: $event -> $script_name"
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

# slash command を ~/.claude/commands/ に symlink
mkdir -p "$COMMANDS_DIR"
for cmd_name in "${COMMANDS[@]}"; do
  cmd_src="$SCRIPT_DIR/commands/$cmd_name"
  cmd_link="$COMMANDS_DIR/$cmd_name"

  if [ ! -f "$cmd_src" ]; then
    echo "  Warning: $cmd_src not found, skipping slash command"
    continue
  fi

  if [ -L "$cmd_link" ]; then
    rm "$cmd_link"
  elif [ -f "$cmd_link" ]; then
    backup="$cmd_link.bak.$(date +%s)"
    mv "$cmd_link" "$backup"
    echo "  Existing file backed up: $backup"
  fi
  ln -s "$cmd_src" "$cmd_link"
  echo "  Installed slash command: /${cmd_name%.md}"
done

echo ""
echo "Done! claude-obsidian-logger is installed."
echo "  Config: $CONFIG_FILE"
echo "  Hooks registered: PostToolUse / UserPromptSubmit / Stop"
echo "  Slash commands installed: $(printf '/%s ' "${COMMANDS[@]%.md}")"
echo ""
echo "Daily rollup is NOT generated automatically (LLM 呼び出しを hook から外したため)."
echo "Run the slash command \`/daily-rollup\` from an interactive Claude Code session"
echo "to generate or update today's rollup (or pass a YYYY-MM-DD date as argument)."
