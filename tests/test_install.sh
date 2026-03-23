#!/usr/bin/env bash
# tests/test_install.sh — install.sh の単体テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALLER="$REPO_ROOT/install.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0; FAIL=0

assert_exists() {
  local path="$1" desc="$2"
  if [ -e "$path" ]; then
    echo "PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — not found: $path"; FAIL=$((FAIL + 1))
  fi
}

assert_not_exists() {
  local path="$1" desc="$2"
  if [ ! -e "$path" ]; then
    echo "PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — unexpectedly found: $path"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qF "$pattern" "$file" 2>/dev/null; then
    echo "PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — pattern not found: $pattern in $file"; FAIL=$((FAIL + 1))
  fi
}

assert_not_contains_file() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qF "$pattern" "$file" 2>/dev/null; then
    echo "PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — unexpectedly found: $pattern in $file"; FAIL=$((FAIL + 1))
  fi
}

echo "=== install.sh tests ==="

export HOME="$TMPDIR_TEST/home"
mkdir -p "$HOME/.claude"
echo '{}' > "$HOME/.claude/settings.json"

# --- Test: install ---
bash "$INSTALLER" 2>/dev/null

assert_exists "$HOME/.local/bin/claude-obsidian-log.sh" "install: シンボリックリンクが作成される"
assert_exists "$HOME/.config/claude-obsidian-logger/config" "install: 設定ファイルが作成される"
assert_contains "$HOME/.claude/settings.json" "PostToolUse" "install: settings.json に PostToolUse hook が追加される"
assert_contains "$HOME/.claude/settings.json" "claude-obsidian-log.sh" "install: settings.json にスクリプトパスが含まれる"

# --- Test: 冪等性（2回実行しても matcher は1つだけ） ---
bash "$INSTALLER" 2>/dev/null
matcher_count="$(grep -c "Edit|Write|MultiEdit|Bash" "$HOME/.claude/settings.json")"
if [ "$matcher_count" -eq 1 ]; then
  echo "PASS: install: 2回実行しても matcher は1つだけ（冪等性）"; PASS=$((PASS + 1))
else
  echo "FAIL: install: matcher が $matcher_count 個ある（冪等性違反）"; FAIL=$((FAIL + 1))
fi

# --- Test: --uninstall ---
bash "$INSTALLER" --uninstall 2>/dev/null

assert_not_exists "$HOME/.local/bin/claude-obsidian-log.sh" "uninstall: シンボリックリンクが削除される"
assert_exists "$HOME/.config/claude-obsidian-logger/config" "uninstall: 設定ファイルは残る"
assert_not_contains_file "$HOME/.claude/settings.json" "claude-obsidian-log.sh" \
  "uninstall: settings.json から hook エントリが削除される"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
