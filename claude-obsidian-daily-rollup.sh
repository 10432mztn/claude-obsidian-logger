#!/usr/bin/env bash
# claude-obsidian-daily-rollup.sh — Claude Code Stop hook (rollup)
# 1日のデイリーノートを総括し、「📋 今日の総括」と「🎯 明日やること」を冒頭に挿入/更新する。
# session-summary.sh の後に走ることを想定（同じ Stop matcher 配下）。
set -euo pipefail
trap 'exit 0' ERR

if ! command -v jq &>/dev/null; then exit 0; fi
if ! command -v claude &>/dev/null; then
  echo "[claude-obsidian-logger] claude command not found. Daily rollup skipped." >&2
  exit 0
fi

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

# --- 入力捨て（payload は使わない、ファイル読み取りのみ）---
cat > /dev/null || true

today="$(date +%Y-%m-%d)"
log_file="$OBSIDIAN_VAULT_PATH/$LOG_DIR/$today.md"

[ -f "$log_file" ] || exit 0

# --- 既存ロールアップを除いた本文を抽出（claude へ渡す材料）---
# ロールアップは <!-- ROLLUP:START --> ... <!-- ROLLUP:END --> で囲む
body="$(awk '
  /<!-- ROLLUP:START -->/ { in_rollup=1; next }
  /<!-- ROLLUP:END -->/   { in_rollup=0; next }
  in_rollup { next }
  { print }
' "$log_file")"

# 本文が極端に短ければスキップ（材料不足）
if [ "${#body}" -lt 200 ]; then
  exit 0
fi

# --- claude CLI で総括＋明日のTODO 生成 ---
prompt="以下は Claude Code の本日（${today}）の作業デイリーノートです。
ユーザーの発言（🗣 で始まるブロック）とセッションサマリー（## セッションサマリー）を読んで、以下の2セクションを日本語で出力してください。

## 📋 今日の総括
3〜5個の箇条書きで、本日の主要な成果。冗長にならず、固有名詞（リポジトリ名・PR番号・機能名）を残して具体的に。

## 🎯 明日やること
3〜5個のチェックボックス（- [ ] ）形式で、未完了タスク・ペンディング事項・次のアクション。重要度順。

出力は上記2セクションのみ。前置きや締めの文は不要。

=== デイリーノート本文 ===
${body:0:8000}"

rollup="$(claude -p "$prompt" 2>/dev/null)"
if [ -z "$rollup" ]; then
  echo "[claude-obsidian-logger] Failed to generate rollup via claude CLI." >&2
  exit 0
fi

# --- ファイル冒頭にロールアップを挿入/更新 ---
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

# 既存ロールアップを除去しつつ、最初の # 見出しの直後に新ロールアップを挿入
awk -v rollup="$rollup" '
  BEGIN { inserted=0 }
  /<!-- ROLLUP:START -->/ { skip=1; next }
  /<!-- ROLLUP:END -->/   { skip=0; next }
  skip { next }
  {
    print
    if (!inserted && $0 ~ /^# [0-9]{4}-[0-9]{2}-[0-9]{2}/) {
      print ""
      print "<!-- ROLLUP:START -->"
      print rollup
      print ""
      print "_最終更新: " strftime("%H:%M") "_"
      print "<!-- ROLLUP:END -->"
      inserted=1
    }
  }
' "$log_file" > "$tmp_file"

mv "$tmp_file" "$log_file"

exit 0
