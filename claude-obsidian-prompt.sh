#!/usr/bin/env bash
# claude-obsidian-prompt.sh — Claude Code UserPromptSubmit hook
# ユーザーが投げたプロンプトをデイリーノートのセクション見出しとして記録する
set -euo pipefail
trap 'exit 0' ERR

if ! command -v jq &>/dev/null; then
  exit 0
fi

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger/config"

_env_vault="${OBSIDIAN_VAULT_PATH:-}"
_env_logdir="${LOG_DIR:-}"
_env_max="${PROMPT_MAX_CHARS:-}"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

OBSIDIAN_VAULT_PATH="${_env_vault:-${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian Vault}}"
LOG_DIR="${_env_logdir:-${LOG_DIR:-Claude Code}}"
PROMPT_MAX_CHARS="${_env_max:-${PROMPT_MAX_CHARS:-200}}"
unset _env_vault _env_logdir _env_max

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null)" || exit 0
[ -z "$prompt" ] && exit 0

# 改行を半角スペースに、先頭の空白除去
clean_prompt="$(printf '%s' "$prompt" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"

# 長すぎるプロンプトは切る
if [ "${#clean_prompt}" -gt "$PROMPT_MAX_CHARS" ]; then
  clean_prompt="${clean_prompt:0:$PROMPT_MAX_CHARS}…"
fi

# プロジェクト判定
payload_cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
project_tag=""
branch_tag=""
if [ -n "$payload_cwd" ] && [ -d "$payload_cwd" ]; then
  if git_root="$(git -C "$payload_cwd" rev-parse --show-toplevel 2>/dev/null)"; then
    project_tag="#$(basename "$git_root")"
    if branch="$(git -C "$git_root" branch --show-current 2>/dev/null)" && [ -n "$branch" ]; then
      branch_tag="#branch/${branch}"
    fi
  else
    project_tag="#$(basename "$payload_cwd")"
  fi
fi

today="$(date +%Y-%m-%d)"
time_now="$(date +%H:%M)"
log_dir_path="$OBSIDIAN_VAULT_PATH/$LOG_DIR"
log_file="$log_dir_path/$today.md"

if [ ! -d "$OBSIDIAN_VAULT_PATH" ]; then
  exit 0
fi
mkdir -p "$log_dir_path"

if [ ! -f "$log_file" ]; then
  printf '# %s\n\n' "$today" > "$log_file"
fi

tags="$project_tag"
[ -n "$branch_tag" ] && tags="$tags $branch_tag"

{
  printf '\n## 🗣 %s — %s\n' "$time_now" "$tags"
  printf '> %s\n\n' "$clean_prompt"
} >> "$log_file"

exit 0
