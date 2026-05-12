#!/usr/bin/env bash
# claude-obsidian-session-summary.sh — Claude Code Stop hook
# セッション終了時に、機械的な統計と主要発言抜粋をデイリーノートに追記する。
# 要約は LLM を呼ばず、対話セッション中の Claude に slash command `/daily-rollup` で生成させる方針。
set -euo pipefail
trap 'exit 0' ERR

if ! command -v jq &>/dev/null; then exit 0; fi

# --- 設定読み込み（env > config > default）---
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger/config"

_env_vault="${OBSIDIAN_VAULT_PATH:-}"
_env_logdir="${LOG_DIR:-}"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

OBSIDIAN_VAULT_PATH="${_env_vault:-${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian Vault}}"
LOG_DIR="${_env_logdir:-${LOG_DIR:-Claude Code}}"
unset _env_vault _env_logdir

if [ ! -d "$OBSIDIAN_VAULT_PATH" ]; then
  echo "[claude-obsidian-logger] Vault not found: $OBSIDIAN_VAULT_PATH" >&2
  exit 0
fi

# --- stdin から payload 読み取り ---
payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)" || exit 0
[ -z "$session_id" ] && exit 0

# --- セッション JSONL を探す ---
session_file="$(find "$HOME/.claude/projects" -name "${session_id}.jsonl" 2>/dev/null | head -1)"
[ -z "$session_file" ] || [ ! -f "$session_file" ] && exit 0

# --- 統計収集 ---
user_count="$(jq -r 'select(.type == "human") | .' "$session_file" 2>/dev/null | jq -s 'length' 2>/dev/null || echo 0)"
edited_files="$(jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit")) |
  .input.file_path // ""
' "$session_file" 2>/dev/null | grep -v '^$' | sort -u)"
edited_count="$(printf '%s\n' "$edited_files" | grep -c .)"
bash_count="$(jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use" and .name == "Bash") |
  .input.command // ""
' "$session_file" 2>/dev/null | grep -cv '^$' || echo 0)"

# --- ユーザーの主要発言を3件抽出（短すぎる返答は除外）---
key_user_msgs="$(jq -r '
  select(.type == "human") |
  .message.content |
  if type == "string" then .
  elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
  else ""
  end
' "$session_file" 2>/dev/null \
  | awk 'length($0) >= 15 && !/^<|^>/' \
  | head -3)"

# プロジェクト
project_dir="$(jq -r 'select(.cwd != null) | .cwd' "$session_file" 2>/dev/null | head -1)"
project_tag=""
if [ -n "$project_dir" ]; then
  project_tag=" #$(basename "$project_dir")"
fi

# 内容が空ならスキップ
if [ "$edited_count" -eq 0 ] && [ -z "$key_user_msgs" ]; then
  exit 0
fi

# --- Obsidian に書き出す ---
today="$(date +%Y-%m-%d)"
time_now="$(date +%H:%M)"
log_dir_path="$OBSIDIAN_VAULT_PATH/$LOG_DIR"
log_file="$log_dir_path/$today.md"

mkdir -p "$log_dir_path"
[ ! -f "$log_file" ] && printf '# %s\n\n' "$today" > "$log_file"

{
  echo ""
  echo "---"
  printf '### 🏁 %s セッション終了%s\n' "$time_now" "$project_tag"
  printf -- '- ユーザー発言: %s 件 / 編集: %s 件 / Bash: %s 件\n' "$user_count" "$edited_count" "$bash_count"
  if [ "$edited_count" -gt 0 ]; then
    echo "- 主な編集ファイル:"
    printf '%s\n' "$edited_files" | head -5 | sed 's|^|    - |'
  fi
  if [ -n "$key_user_msgs" ]; then
    echo "- 主な依頼:"
    printf '%s\n' "$key_user_msgs" | sed 's|^|    > |'
  fi
  echo ""
} >> "$log_file"

exit 0
