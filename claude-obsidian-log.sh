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

# --- 出力先パス ---
today="$(date +%Y-%m-%d)"
time_now="$(date +%H:%M)"
log_dir_path="$OBSIDIAN_VAULT_PATH/$LOG_DIR"
log_file="$log_dir_path/$today.md"

# vault ディレクトリ存在確認
if [ ! -d "$OBSIDIAN_VAULT_PATH" ]; then
  echo "[claude-obsidian-logger] Vault not found: $OBSIDIAN_VAULT_PATH" >&2
  exit 0
fi

mkdir -p "$log_dir_path"

# ファイルが存在しなければヘッダ作成
if [ ! -f "$log_file" ]; then
  printf '# %s\n\n' "$today" > "$log_file"
fi

# --- ツール別の対象情報を抽出 ---
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

case "$tool_name" in
  Edit|Write|MultiEdit)
    raw_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || { exit 0; }
    # CLAUDE_PROJECT_DIR からの相対パスを計算（外にある場合は basename）
    if [[ "$raw_path" == "$project_dir/"* ]]; then
      target="${raw_path#"$project_dir/"}"
    else
      target="$(basename "$raw_path")"
    fi
    ;;
  Bash)
    raw_cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || { exit 0; }
    if [ "${#raw_cmd}" -gt 120 ]; then
      target="${raw_cmd:0:120}..."
    else
      target="$raw_cmd"
    fi
    ;;
esac

# --- タグ取得 ---
project_tag="#$(basename "$project_dir")"

branch_tag=""
if git -C "$project_dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  branch="$(git -C "$project_dir" branch --show-current 2>/dev/null)"
  if [ -n "$branch" ]; then
    branch_tag="#branch/$branch"
  fi
fi

# --- ログ行を追記 ---
{
  printf '### %s - %s: %s\n' "$time_now" "$tool_name" "$target"
  echo "- プロジェクト: $project_tag"
  if [ -n "$branch_tag" ]; then
    echo "- ブランチ: $branch_tag"
  fi
  echo ""
} >> "$log_file"

exit 0
