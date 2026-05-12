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
# 優先順位: 環境変数 > 設定ファイル > デフォルト
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger/config"

# 環境変数を退避（config が上書きしないように）
_env_vault="${OBSIDIAN_VAULT_PATH:-}"
_env_logdir="${LOG_DIR:-}"
_env_skip="${SKIP_BASH_PATTERN:-}"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# 環境変数が設定されていればそれを優先
OBSIDIAN_VAULT_PATH="${_env_vault:-${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian Vault}}"
LOG_DIR="${_env_logdir:-${LOG_DIR:-Claude Code}}"
SKIP_BASH_PATTERN="${_env_skip:-${SKIP_BASH_PATTERN:-^(ls|cat|head|tail|pwd|which|file|stat|find|echo|printf|grep |/bin/ls|wc |type |whoami|env$|env |sleep )}}"
unset _env_vault _env_logdir _env_skip

# --- stdin から JSON を読み取り ---
payload="$(cat)"

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || { exit 0; }
if [ -z "$tool_name" ]; then
  exit 0
fi

# 対象ツール以外はスキップ
case "$tool_name" in
  Edit|Write|MultiEdit|Bash) ;;
  *) exit 0 ;;
esac

# --- payload から共通情報を取得 ---
payload_cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

# --- ツール別の対象情報を抽出 ---
target=""
anchor_dir=""

case "$tool_name" in
  Edit|Write|MultiEdit)
    raw_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    [ -z "$raw_path" ] && exit 0

    # プロジェクト判定のアンカーは編集対象ファイルのディレクトリ
    anchor_dir="$(dirname "$raw_path")"

    # 表示用パスは git root からの相対、無理なら basename
    if git_root="$(git -C "$anchor_dir" rev-parse --show-toplevel 2>/dev/null)"; then
      target="${raw_path#"$git_root/"}"
    else
      target="$(basename "$raw_path")"
    fi
    ;;
  Bash)
    raw_cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    description="$(printf '%s' "$payload" | jq -r '.tool_input.description // empty' 2>/dev/null)"
    [ -z "$raw_cmd" ] && exit 0

    # ノイズフィルタ（読み取り系コマンドはスキップ）
    if [[ "$raw_cmd" =~ $SKIP_BASH_PATTERN ]]; then
      exit 0
    fi

    # description があれば優先、なければコマンド先頭80字
    if [ -n "$description" ]; then
      target="$description"
    else
      if [ "${#raw_cmd}" -gt 80 ]; then
        target="${raw_cmd:0:80}…"
      else
        target="$raw_cmd"
      fi
    fi

    anchor_dir="$payload_cwd"
    ;;
esac

# --- プロジェクト・ブランチ判定 ---
# 1) anchor_dir の git root を最優先
# 2) ダメなら payload_cwd の git root
# 3) どっちも無理なら anchor_dir / payload_cwd の basename
project_root=""
if [ -n "$anchor_dir" ] && [ -d "$anchor_dir" ]; then
  project_root="$(git -C "$anchor_dir" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$project_root" ] && [ -n "$payload_cwd" ] && [ -d "$payload_cwd" ]; then
  project_root="$(git -C "$payload_cwd" rev-parse --show-toplevel 2>/dev/null || true)"
fi

if [ -n "$project_root" ]; then
  project_name="$(basename "$project_root")"
  branch="$(git -C "$project_root" branch --show-current 2>/dev/null || true)"
else
  project_name="$(basename "${anchor_dir:-${payload_cwd:-unknown}}")"
  branch=""
fi

project_tag="#${project_name}"
branch_tag=""
[ -n "$branch" ] && branch_tag="#branch/${branch}"

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

# --- ログ行を追記 ---
# tool ごとに簡潔なアイコンを付ける
case "$tool_name" in
  Edit)      icon="✏️" ;;
  Write)     icon="📝" ;;
  MultiEdit) icon="✂️" ;;
  Bash)      icon="⚡" ;;
  *)         icon="·" ;;
esac

tags="$project_tag"
[ -n "$branch_tag" ] && tags="$tags $branch_tag"

{
  printf '%s\n' "- **${time_now}** ${icon} ${tool_name} — ${target} _(${tags})_"
} >> "$log_file"

exit 0
