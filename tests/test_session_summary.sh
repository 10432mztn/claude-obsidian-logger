#!/usr/bin/env bash
# tests/test_session_summary.sh — claude-obsidian-session-summary.sh の単体テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SUMMARY="$REPO_ROOT/claude-obsidian-session-summary.sh"

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/summary-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0; FAIL=0

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qF "$pattern" "$file" 2>/dev/null; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  Expected to find: $pattern"
    echo "  In file: $file"
    FAIL=$((FAIL + 1))
  fi
}

FAKE_HOME="$TMPDIR_TEST/home"
VAULT="$TMPDIR_TEST/vault"
SESSION_ID="test-session-0001"
mkdir -p "$FAKE_HOME/.claude/projects/-tmp-proj" "$VAULT"

cat > "$FAKE_HOME/.claude/projects/-tmp-proj/$SESSION_ID.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"ログ集計の仕組みを直してほしい"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/proj/a.sh"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"edit-1","content":"ファイルの編集が完了しました"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"テストも一緒に足しておいてください"}]}}
JSONL

printf '{"session_id":"%s","cwd":"/tmp/proj"}' "$SESSION_ID" |
  HOME="$FAKE_HOME" OBSIDIAN_VAULT_PATH="$VAULT" LOG_DIR="logs" bash "$SUMMARY"

LOG_FILE="$(find "$VAULT" -name '*.md' | head -1)"

echo "=== Test: transcript の type=user を発言として数える ==="
assert_contains "$LOG_FILE" "ユーザー発言: 2 件" "ツールの実行結果を発言数に含めない"

echo "=== Test: 主な依頼に user の発言が載る ==="
assert_contains "$LOG_FILE" "ログ集計の仕組みを直してほしい" "string content is extracted"
assert_contains "$LOG_FILE" "テストも一緒に足しておいてください" "array content is extracted"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
