#!/usr/bin/env bash
# tests/test_logger.sh — claude-obsidian-log.sh の単体テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOGGER="$REPO_ROOT/claude-obsidian-log.sh"

TMPDIR_TEST="$(mktemp -d)"
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

assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qF "$pattern" "$file" 2>/dev/null; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  Expected NOT to find: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert_matches() {
  # grep -E でパターンマッチ
  local file="$1" pattern="$2" desc="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  Expected regex match: $pattern"
    echo "  In file: $file"
    FAIL=$((FAIL + 1))
  fi
}

run_logger() {
  local json="$1"
  OBSIDIAN_VAULT_PATH="$TMPDIR_TEST/vault" \
  LOG_DIR="Claude Code" \
  CLAUDE_PROJECT_DIR="/Users/test/dev/my-project" \
  HOME="$TMPDIR_TEST" \
    printf '%s' "$json" | bash "$LOGGER" 2>/dev/null
}

today="$(date +%Y-%m-%d)"
vault_dir="$TMPDIR_TEST/vault/Claude Code"
log_file="$vault_dir/$today.md"

echo "=== claude-obsidian-log.sh tests ==="

# --- Test: Edit ツールの記録 ---
mkdir -p "$vault_dir"
run_logger '{"tool_name":"Edit","tool_input":{"file_path":"/Users/test/dev/my-project/src/main.ts"}}'

assert_contains "$log_file" "Edit: src/main.ts" "Edit: CLAUDE_PROJECT_DIR からの相対パスが記録される"
assert_contains "$log_file" "#my-project" "Edit: プロジェクトタグが記録される"
# タイムスタンプは HH:MM 形式で存在するか確認（分境界に依存しない）
assert_matches "$log_file" "^### [0-9]{2}:[0-9]{2} - Edit:" "Edit: HH:MM 形式のタイムスタンプが記録される"

# --- Test: Write ツールの記録 ---
run_logger '{"tool_name":"Write","tool_input":{"file_path":"/Users/test/dev/my-project/README.md"}}'

assert_contains "$log_file" "Write: README.md" "Write: ファイル名が記録される"

# --- Test: MultiEdit ツールの記録 ---
run_logger '{"tool_name":"MultiEdit","tool_input":{"file_path":"/Users/test/dev/my-project/src/index.ts"}}'

assert_contains "$log_file" "MultiEdit: src/index.ts" "MultiEdit: 相対パスが記録される"

# --- Test: CLAUDE_PROJECT_DIR 外のファイルは basename ---
run_logger '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/other-project/secret.ts"}}'

assert_contains "$log_file" "Edit: secret.ts" "Edit: PROJECT_DIR 外のファイルは basename で記録される"

# --- Test: Bash ツールの記録 ---
run_logger '{"tool_name":"Bash","tool_input":{"command":"go test ./..."}}'

assert_contains "$log_file" "Bash: go test ./..." "Bash: コマンドが記録される"

# --- Test: Bash コマンド 120 文字切り詰め ---
long_cmd="$(python3 -c "print('a' * 150)")"
run_logger "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long_cmd\"}}"

assert_contains "$log_file" "..." "Bash: 長いコマンドは末尾に ... が付く"
assert_not_contains "$log_file" "$(python3 -c "print('a' * 150)")" "Bash: 150文字のコマンドはそのまま記録されない"

# --- Test: 不正 JSON は exit 0 ---
result=0
OBSIDIAN_VAULT_PATH="$TMPDIR_TEST/vault" LOG_DIR="Claude Code" HOME="$TMPDIR_TEST" \
  printf 'not json' | bash "$LOGGER" 2>/dev/null || result=$?
if [ "$result" -eq 0 ]; then
  echo "PASS: 不正 JSON でも exit 0"; PASS=$((PASS + 1))
else
  echo "FAIL: 不正 JSON で非ゼロ終了 ($result)"; FAIL=$((FAIL + 1))
fi

# --- Test: vault 不在は exit 0 ---
result=0
OBSIDIAN_VAULT_PATH="$TMPDIR_TEST/nonexistent-vault" LOG_DIR="Claude Code" HOME="$TMPDIR_TEST" \
CLAUDE_PROJECT_DIR="/Users/test/dev/my-project" \
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/f.ts"}}' | bash "$LOGGER" 2>/dev/null || result=$?
if [ "$result" -eq 0 ]; then
  echo "PASS: vault 不在でも exit 0"; PASS=$((PASS + 1))
else
  echo "FAIL: vault 不在で非ゼロ終了 ($result)"; FAIL=$((FAIL + 1))
fi

# --- Test: git リポジトリ外はブランチタグ省略 ---
non_git_dir="$TMPDIR_TEST/non-git-project"
mkdir -p "$non_git_dir"
non_git_log="$TMPDIR_TEST/vault/Claude Code/$today.md"

OBSIDIAN_VAULT_PATH="$TMPDIR_TEST/vault" LOG_DIR="Claude Code" \
CLAUDE_PROJECT_DIR="$non_git_dir" HOME="$TMPDIR_TEST" \
  printf '{"tool_name":"Write","tool_input":{"file_path":"'"$non_git_dir"'/foo.ts"}}' \
  | bash "$LOGGER" 2>/dev/null

assert_contains "$non_git_log" "Write: foo.ts" "git 外: ファイルは記録される"
assert_not_contains "$non_git_log" "#branch/" "git 外: ブランチタグは記録されない"

# --- Test: config 不在 → デフォルト値で動作 ---
no_config_home="$TMPDIR_TEST/no-config-home"
mkdir -p "$no_config_home"
default_vault="$no_config_home/Documents/Obsidian Vault"
mkdir -p "$default_vault"

HOME="$no_config_home" CLAUDE_PROJECT_DIR="/Users/test/dev/my-project" \
  printf '{"tool_name":"Write","tool_input":{"file_path":"/Users/test/dev/my-project/f.ts"}}' \
  | bash "$LOGGER" 2>/dev/null

no_config_log="$default_vault/Claude Code/$today.md"
if [ -f "$no_config_log" ]; then
  echo "PASS: config 不在: デフォルト vault にログが書き込まれる"; PASS=$((PASS + 1))
else
  echo "FAIL: config 不在: ログが書き込まれなかった ($no_config_log)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
