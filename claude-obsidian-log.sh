#!/usr/bin/env bash
# claude-obsidian-log.sh — Claude Code PostToolUse hook
set -euo pipefail
trap 'exit 0' ERR

# --- jq チェック ---
if ! command -v jq &>/dev/null; then
  echo "[claude-obsidian-logger] jq not found. Install jq to enable logging." >&2
  exit 0
fi

# --- 設定読み込み ---
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger/config"
OBSIDIAN_VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian Vault}"
LOG_DIR="${LOG_DIR:-Claude Code}"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# --- stdin から JSON を読み取り ---
payload="$(cat)"

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || { exit 0; }
if [ -z "$tool_name" ]; then
  echo "[claude-obsidian-logger] tool_name not found in payload." >&2
  exit 0
fi

# 対象ツール以外はスキップ
case "$tool_name" in
  Edit|Write|MultiEdit|Bash) ;;
  *) exit 0 ;;
esac

exit 0
