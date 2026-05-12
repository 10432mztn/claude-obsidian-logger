#!/usr/bin/env bash
# claude-obsidian-session-summary.sh — Claude Code Stop hook
# セッション終了時に作業サマリーを Obsidian のデイリーノートに追記する
set -euo pipefail
trap 'exit 0' ERR

# --- 依存チェック ---
if ! command -v jq &>/dev/null; then exit 0; fi
if ! command -v claude &>/dev/null; then
  echo "[claude-obsidian-logger] claude command not found. Session summary skipped." >&2
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

# --- vault 確認 ---
if [ ! -d "$OBSIDIAN_VAULT_PATH" ]; then
  echo "[claude-obsidian-logger] Vault not found: $OBSIDIAN_VAULT_PATH" >&2
  exit 0
fi

# --- stdin から payload 読み取り ---
payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)" || { exit 0; }
if [ -z "$session_id" ]; then
  echo "[claude-obsidian-logger] session_id not found in Stop payload." >&2
  exit 0
fi

# --- セッション JSONL を探す ---
session_file="$(find "$HOME/.claude/projects" -name "${session_id}.jsonl" 2>/dev/null | head -1)"
if [ -z "$session_file" ] || [ ! -f "$session_file" ]; then
  echo "[claude-obsidian-logger] Session file not found for: $session_id" >&2
  exit 0
fi

# --- 会話内容を抽出 ---
# ユーザーのメッセージ（最初の3件）
user_messages="$(jq -r '
  select(.type == "human") |
  .message.content |
  if type == "string" then .
  elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
  else ""
  end
' "$session_file" 2>/dev/null | grep -v '^$' | head -3)"

# 変更されたファイル
edited_files="$(jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit")) |
  .input.file_path // ""
' "$session_file" 2>/dev/null | grep -v '^$' | sort -u)"

# プロジェクトディレクトリ
project_dir="$(jq -r 'select(.cwd != null) | .cwd' "$session_file" 2>/dev/null | head -1)"
project_name=""
if [ -n "$project_dir" ]; then
  project_name="$(basename "$project_dir")"
fi

# 内容が空なら記録しない
if [ -z "$user_messages" ] && [ -z "$edited_files" ]; then
  exit 0
fi

# --- claude CLI でサマリー生成 ---
prompt="以下は Claude Code のセッション情報です。日本語で以下の2セクションを書いてください。

## やったこと
1〜3個の箇条書きで、このセッションで何を達成したか。

## 次のステップ
このセッションで触れたが未完了のタスク、明日以降にやるべきこと、ペンディング事項を1〜3個。なければ「特になし」と書く。

=== ユーザーの発言（抜粋）===
${user_messages:0:3000}

=== 変更されたファイル ===
${edited_files:-（なし）}

出力（上記2セクションのみ、見出しは ## で）："

summary="$(claude -p "$prompt" 2>/dev/null)"
if [ -z "$summary" ]; then
  echo "[claude-obsidian-logger] Failed to generate summary via claude CLI." >&2
  exit 0
fi

# --- Obsidian に書き出す ---
today="$(date +%Y-%m-%d)"
time_now="$(date +%H:%M)"
log_dir_path="$OBSIDIAN_VAULT_PATH/$LOG_DIR"
log_file="$log_dir_path/$today.md"

mkdir -p "$log_dir_path"
if [ ! -f "$log_file" ]; then
  printf '# %s\n\n' "$today" > "$log_file"
fi

project_tag=""
if [ -n "$project_name" ]; then
  project_tag=" #${project_name}"
fi

{
  echo "---"
  printf '## %s セッションサマリー%s\n\n' "$time_now" "$project_tag"
  printf '%s\n\n' "$summary"
} >> "$log_file"

exit 0
