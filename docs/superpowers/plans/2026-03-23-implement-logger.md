# claude-obsidian-logger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code の PostToolUse hook から呼ばれ、Obsidian デイリーノートに作業ログを追記するシェルスクリプトツールを実装する。

**Architecture:** `claude-obsidian-log.sh` が stdin から JSON を読み取り、jq でパースして Obsidian vault のデイリーノートに Markdown を追記する。`install.sh` がシンボリックリンク作成・設定ファイル生成・`~/.claude/settings.json` への hook 登録を担う。テストは Bash スクリプトで stdin に JSON を渡して出力ファイルの内容を検証する。

**Tech Stack:** Bash, jq, Claude Code hooks (PostToolUse), Obsidian Markdown

---

## 設計上の決定事項

**ファイルパス表示**: 設計ドキュメントの出力例は `Edit: src/agent/internal/collector.go`（相対パス）を示しているため、`$CLAUDE_PROJECT_DIR` プレフィックスを strip して相対パスを記録する。ファイルが `CLAUDE_PROJECT_DIR` 外にある場合は `basename` にフォールバック。

---

## File Structure

| ファイル | 役割 |
|----------|------|
| `claude-obsidian-log.sh` | メインロガースクリプト（hook から呼ばれる） |
| `install.sh` | インストール／アンインストールスクリプト |
| `README.md` | セットアップ・使い方・出力例 |
| `tests/test_logger.sh` | `claude-obsidian-log.sh` の単体テスト |
| `tests/test_install.sh` | `install.sh` のテスト |

---

## Task 1: テストフレームワーク（test_logger.sh の骨格）

**Files:**
- Create: `tests/test_logger.sh`

- [ ] **Step 1: テストファイルを作成する**

```bash
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
  if grep -qF "$pattern" "$file"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    echo "  Expected to find: $pattern"
    echo "  In file: $file"
    ((FAIL++))
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qF "$pattern" "$file"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    echo "  Expected NOT to find: $pattern"
    ((FAIL++))
  fi
}

assert_matches() {
  # grep -E でパターンマッチ
  local file="$1" pattern="$2" desc="$3"
  if grep -qE "$pattern" "$file"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    echo "  Expected regex match: $pattern"
    echo "  In file: $file"
    ((FAIL++))
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
```

- [ ] **Step 2: 実行権限を付与する**

```bash
chmod +x tests/test_logger.sh
```

- [ ] **Step 3: テストを実行してスクリプトが存在しないためエラーになることを確認する**

```bash
bash tests/test_logger.sh
```

Expected: `bash: .../claude-obsidian-log.sh: No such file or directory` などのエラー

- [ ] **Step 4: コミット**

```bash
git add tests/test_logger.sh
git commit -m "test: add test framework skeleton for claude-obsidian-log.sh"
```

---

## Task 2: Edit/Write/MultiEdit の記録テスト追加

**Files:**
- Modify: `tests/test_logger.sh`（サマリ行の前に追記）

> **Note:** ファイルパスは `CLAUDE_PROJECT_DIR` (`/Users/test/dev/my-project`) からの相対パスで記録される。

- [ ] **Step 1: vault ディレクトリを作成し Edit テストを追記する**

`run_logger` 定義の後に追加:

```bash
# --- Test: Edit ツールの記録 ---
mkdir -p "$vault_dir"
run_logger '{"tool_name":"Edit","tool_input":{"file_path":"/Users/test/dev/my-project/src/main.ts"}}'

assert_contains "$log_file" "Edit: src/main.ts" "Edit: CLAUDE_PROJECT_DIR からの相対パスが記録される"
assert_contains "$log_file" "#my-project" "Edit: プロジェクトタグが記録される"
# タイムスタンプは HH:MM 形式で存在するか確認（分境界に依存しない）
assert_matches "$log_file" "^### [0-9]{2}:[0-9]{2} - Edit:" "Edit: HH:MM 形式のタイムスタンプが記録される"
```

- [ ] **Step 2: Write テストを追記する**

```bash
# --- Test: Write ツールの記録 ---
run_logger '{"tool_name":"Write","tool_input":{"file_path":"/Users/test/dev/my-project/README.md"}}'

assert_contains "$log_file" "Write: README.md" "Write: ファイル名が記録される"
```

- [ ] **Step 3: MultiEdit テストを追記する**

```bash
# --- Test: MultiEdit ツールの記録 ---
run_logger '{"tool_name":"MultiEdit","tool_input":{"file_path":"/Users/test/dev/my-project/src/index.ts"}}'

assert_contains "$log_file" "MultiEdit: src/index.ts" "MultiEdit: 相対パスが記録される"
```

- [ ] **Step 4: ファイル外パスは basename にフォールバックするテストを追記する**

```bash
# --- Test: CLAUDE_PROJECT_DIR 外のファイルは basename ---
run_logger '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/other-project/secret.ts"}}'

assert_contains "$log_file" "Edit: secret.ts" "Edit: PROJECT_DIR 外のファイルは basename で記録される"
```

- [ ] **Step 5: サマリ行を追加する**

```bash
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 6: テストを実行してスクリプトが存在しないためエラーになることを確認する**

```bash
bash tests/test_logger.sh
```

Expected: エラー（logger スクリプトがまだ存在しない）

- [ ] **Step 7: コミット**

```bash
git add tests/test_logger.sh
git commit -m "test: add Edit/Write/MultiEdit recording tests"
```

---

## Task 3: Bash・エラーハンドリング・エッジケースのテスト追加

**Files:**
- Modify: `tests/test_logger.sh`（サマリ行の前に追記）

- [ ] **Step 1: Bash ツール（通常コマンド）のテストを追加する**

```bash
# --- Test: Bash ツールの記録 ---
run_logger '{"tool_name":"Bash","tool_input":{"command":"go test ./..."}}'

assert_contains "$log_file" "Bash: go test ./..." "Bash: コマンドが記録される"
```

- [ ] **Step 2: Bash コマンド 120 文字切り詰めテストを追加する**

```bash
# --- Test: Bash コマンド 120 文字切り詰め ---
long_cmd="$(python3 -c "print('a' * 150)")"
run_logger "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long_cmd\"}}"

assert_contains "$log_file" "..." "Bash: 長いコマンドは末尾に ... が付く"
assert_not_contains "$log_file" "$(python3 -c "print('a' * 150)")" "Bash: 150文字のコマンドはそのまま記録されない"
```

- [ ] **Step 3: 不正 JSON の場合に exit 0 で終了するテストを追加する**

```bash
# --- Test: 不正 JSON は exit 0 ---
result=0
OBSIDIAN_VAULT_PATH="$TMPDIR_TEST/vault" LOG_DIR="Claude Code" HOME="$TMPDIR_TEST" \
  printf 'not json' | bash "$LOGGER" 2>/dev/null || result=$?
if [ "$result" -eq 0 ]; then
  echo "PASS: 不正 JSON でも exit 0"; ((PASS++))
else
  echo "FAIL: 不正 JSON で非ゼロ終了 ($result)"; ((FAIL++))
fi
```

- [ ] **Step 4: vault ディレクトリが存在しない場合に exit 0 で終了するテストを追加する**

```bash
# --- Test: vault 不在は exit 0 ---
result=0
OBSIDIAN_VAULT_PATH="$TMPDIR_TEST/nonexistent-vault" LOG_DIR="Claude Code" HOME="$TMPDIR_TEST" \
CLAUDE_PROJECT_DIR="/Users/test/dev/my-project" \
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/f.ts"}}' | bash "$LOGGER" 2>/dev/null || result=$?
if [ "$result" -eq 0 ]; then
  echo "PASS: vault 不在でも exit 0"; ((PASS++))
else
  echo "FAIL: vault 不在で非ゼロ終了 ($result)"; ((FAIL++))
fi
```

- [ ] **Step 5: git リポジトリ外ではブランチタグが省略されるテストを追加する**

```bash
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
```

- [ ] **Step 6: config ファイルが存在しない場合にデフォルト値で動作するテストを追加する**

```bash
# --- Test: config 不在 → デフォルト値で動作 ---
no_config_home="$TMPDIR_TEST/no-config-home"
mkdir -p "$no_config_home"
default_vault="$no_config_home/Documents/Obsidian Vault"
mkdir -p "$default_vault"

HOME="$no_config_home" CLAUDE_PROJECT_DIR="/Users/test/dev/my-project" \
  printf '{"tool_name":"Write","tool_input":{"file_path":"/Users/test/dev/my-project/f.ts"}}' \
  | bash "$LOGGER" 2>/dev/null

assert_exists_dir() {
  local path="$1" desc="$2"
  if [ -d "$path" ]; then
    echo "PASS: $desc"; ((PASS++))
  else
    echo "FAIL: $desc — not found: $path"; ((FAIL++))
  fi
}

no_config_log="$default_vault/Claude Code/$today.md"
if [ -f "$no_config_log" ]; then
  echo "PASS: config 不在: デフォルト vault にログが書き込まれる"; ((PASS++))
else
  echo "FAIL: config 不在: ログが書き込まれなかった ($no_config_log)"; ((FAIL++))
fi
```

- [ ] **Step 7: コミット**

```bash
git add tests/test_logger.sh
git commit -m "test: add Bash/error-handling/edge-case tests for logger"
```

---

## Task 4a: `claude-obsidian-log.sh` の骨格実装

**Files:**
- Create: `claude-obsidian-log.sh`

- [ ] **Step 1: スクリプトの骨格（エラーハンドリング・設定読み込みのみ）を作成する**

```bash
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

exit 0
```

- [ ] **Step 2: 実行権限を付与する**

```bash
chmod +x claude-obsidian-log.sh
```

- [ ] **Step 3: コミット**

```bash
git add claude-obsidian-log.sh
git commit -m "feat: add claude-obsidian-log.sh skeleton with config loading"
```

---

## Task 4b: stdin JSON パースとツール種別振り分けを実装

**Files:**
- Modify: `claude-obsidian-log.sh`（`exit 0` の前に追加）

- [ ] **Step 1: JSON パースとツール種別チェックを追加する**

`exit 0` を以下に差し替え:

```bash
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
```

- [ ] **Step 2: テストを実行して不正 JSON テストが PASS することを確認する**

```bash
bash tests/test_logger.sh 2>&1 | grep -E "PASS|FAIL|Results"
```

Expected: 不正JSONテストが PASS（他はまだ FAIL）

- [ ] **Step 3: コミット**

```bash
git add claude-obsidian-log.sh
git commit -m "feat: add stdin JSON parsing and tool-type filtering"
```

---

## Task 4c: 出力先パスとファイルヘッダ作成を実装

**Files:**
- Modify: `claude-obsidian-log.sh`

- [ ] **Step 1: vault チェックとファイル初期化ロジックを追加する**

最後の `exit 0` の前に追加:

```bash
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
```

- [ ] **Step 2: テストを実行して vault 不在テストが PASS することを確認する**

```bash
bash tests/test_logger.sh 2>&1 | grep -E "vault|PASS|FAIL"
```

- [ ] **Step 3: コミット**

```bash
git add claude-obsidian-log.sh
git commit -m "feat: add vault path check and daily note header creation"
```

---

## Task 4d: ツール別情報抽出・タグ取得・追記を実装

**Files:**
- Modify: `claude-obsidian-log.sh`

- [ ] **Step 1: ツール別対象情報の抽出ロジックを追加する**

最後の `exit 0` の前に追加:

```bash
# --- ツール別の対象情報を抽出 ---
case "$tool_name" in
  Edit|Write|MultiEdit)
    raw_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || { exit 0; }
    # CLAUDE_PROJECT_DIR からの相対パスを計算（外にある場合は basename）
    project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
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
```

- [ ] **Step 2: タグ取得ロジックを追加する**

```bash
# --- タグ取得 ---
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
project_tag="#$(basename "$project_dir")"

branch_tag=""
if git -C "$project_dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  branch="$(git -C "$project_dir" branch --show-current 2>/dev/null)"
  if [ -n "$branch" ]; then
    branch_tag="#branch/$branch"
  fi
fi
```

> **Note:** `project_dir` は Step 1 で既に設定しているため、Step 2 では `${CLAUDE_PROJECT_DIR:-$(pwd)}` の再計算は不要。Step 1 の変数を再利用する（ただしスコープに注意：`case` ブロックで `project_dir` を設定し、後続のタグ取得で使う）。

- [ ] **Step 3: ログ追記ロジックを追加する**

```bash
# --- ログ行を追記 ---
{
  printf '### %s - %s: %s\n' "$time_now" "$tool_name" "$target"
  printf '- プロジェクト: %s\n' "$project_tag"
  if [ -n "$branch_tag" ]; then
    printf '- ブランチ: %s\n' "$branch_tag"
  fi
  printf '\n'
} >> "$log_file"

exit 0
```

- [ ] **Step 4: テストを実行して全件 PASS することを確認する**

```bash
bash tests/test_logger.sh
```

Expected: `Results: N passed, 0 failed`

- [ ] **Step 5: コミット**

```bash
git add claude-obsidian-log.sh
git commit -m "feat: add tool input extraction, tag generation, and log append"
```

---

## Task 5: `install.sh` のテスト追加

**Files:**
- Create: `tests/test_install.sh`

- [ ] **Step 1: テストファイルを作成する**

```bash
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
    echo "PASS: $desc"; ((PASS++))
  else
    echo "FAIL: $desc — not found: $path"; ((FAIL++))
  fi
}

assert_not_exists() {
  local path="$1" desc="$2"
  if [ ! -e "$path" ]; then
    echo "PASS: $desc"; ((PASS++))
  else
    echo "FAIL: $desc — unexpectedly found: $path"; ((FAIL++))
  fi
}

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qF "$pattern" "$file"; then
    echo "PASS: $desc"; ((PASS++))
  else
    echo "FAIL: $desc — pattern not found: $pattern in $file"; ((FAIL++))
  fi
}

assert_not_contains_file() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qF "$pattern" "$file" 2>/dev/null; then
    echo "PASS: $desc"; ((PASS++))
  else
    echo "FAIL: $desc — unexpectedly found: $pattern in $file"; ((FAIL++))
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
  echo "PASS: install: 2回実行しても matcher は1つだけ（冪等性）"; ((PASS++))
else
  echo "FAIL: install: matcher が $matcher_count 個ある（冪等性違反）"; ((FAIL++))
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
```

- [ ] **Step 2: 実行権限を付与する**

```bash
chmod +x tests/test_install.sh
```

- [ ] **Step 3: テストを実行してスクリプトが存在しないためエラーになることを確認する**

```bash
bash tests/test_install.sh
```

Expected: エラー or テスト失敗（install.sh がまだ存在しない）

- [ ] **Step 4: コミット**

```bash
git add tests/test_install.sh
git commit -m "test: add install.sh tests including idempotency and uninstall hook removal"
```

---

## Task 6: `install.sh` の実装

**Files:**
- Create: `install.sh`

- [ ] **Step 1: スクリプトを作成する**

```bash
#!/usr/bin/env bash
# install.sh — claude-obsidian-logger のセットアップ / アンインストール
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGGER_SCRIPT="$SCRIPT_DIR/claude-obsidian-log.sh"
SYMLINK_DIR="$HOME/.local/bin"
SYMLINK="$SYMLINK_DIR/claude-obsidian-log.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-obsidian-logger"
CONFIG_FILE="$CONFIG_DIR/config"
SETTINGS="$HOME/.claude/settings.json"
MATCHER="Edit|Write|MultiEdit|Bash"

# --- アンインストール ---
if [ "${1:-}" = "--uninstall" ]; then
  echo "Uninstalling claude-obsidian-logger..."

  if [ -L "$SYMLINK" ]; then
    rm "$SYMLINK"
    echo "  Removed symlink: $SYMLINK"
  fi

  if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    tmp="$(mktemp)"
    jq --arg m "$MATCHER" \
      'del(.hooks.PostToolUse[]? | select(.matcher == $m))' \
      "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  Removed hook from: $SETTINGS"
  fi

  echo "Done. Config file retained at: $CONFIG_FILE"
  exit 0
fi

# --- インストール ---
echo "Installing claude-obsidian-logger..."

# jq チェック
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it first:" >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Ubuntu: sudo apt install jq" >&2
  exit 1
fi

# 設定ファイル作成
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
# claude-obsidian-logger configuration
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"
LOG_DIR="Claude Code"
EOF
  echo "  Created config: $CONFIG_FILE"
else
  echo "  Config already exists: $CONFIG_FILE (skipped)"
fi

# シンボリックリンク作成
mkdir -p "$SYMLINK_DIR"
if [ -L "$SYMLINK" ]; then
  rm "$SYMLINK"
fi
ln -s "$LOGGER_SCRIPT" "$SYMLINK"
echo "  Created symlink: $SYMLINK -> $LOGGER_SCRIPT"

# PATH 案内
if ! echo "$PATH" | grep -q "$SYMLINK_DIR"; then
  echo "  Note: Add $SYMLINK_DIR to your PATH:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# settings.json に hook 追加（冪等）
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

already="$(jq --arg m "$MATCHER" \
  '[.hooks.PostToolUse[]? | select(.matcher == $m)] | length' \
  "$SETTINGS" 2>/dev/null || echo 0)"

if [ "$already" -gt 0 ]; then
  echo "  Hook already registered in: $SETTINGS (skipped)"
else
  tmp="$(mktemp)"
  jq --arg m "$MATCHER" --arg cmd "$SYMLINK" '
    .hooks.PostToolUse = (
      (.hooks.PostToolUse // []) +
      [{"matcher": $m, "hooks": [{"type": "command", "command": $cmd}]}]
    )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  Added hook to: $SETTINGS"
fi

echo ""
echo "Done! claude-obsidian-logger is installed."
echo "Edit config to set your vault path: $CONFIG_FILE"
```

- [ ] **Step 2: 実行権限を付与する**

```bash
chmod +x install.sh
```

- [ ] **Step 3: テストを実行して全件 PASS することを確認する**

```bash
bash tests/test_install.sh
```

Expected: `Results: N passed, 0 failed`

- [ ] **Step 4: コミット**

```bash
git add install.sh
git commit -m "feat: implement install.sh with idempotent hook registration and uninstall"
```

---

## Task 7: `README.md` の作成

**Files:**
- Create: `README.md`

- [ ] **Step 1: README.md を作成する**

```markdown
# claude-obsidian-logger

Claude Code の [hook 機能](https://docs.anthropic.com/en/docs/claude-code/hooks) を使って、作業進捗を Obsidian のデイリーノートにリアルタイム記録するシェルスクリプトツール。

## 特徴

- **トークン消費ゼロ** — hook はモデル外で実行されるため
- **アクション単位で記録** — Edit / Write / MultiEdit / Bash ごとに自動追記
- **タグ自動付与** — プロジェクト名・ブランチ名を Obsidian タグとして記録
- **プロジェクト横断検索** — タグ検索で全プロジェクトの作業履歴を横断参照

## 出力例

`~/Documents/Obsidian Vault/Claude Code/2026-03-23.md`:

\```markdown
# 2026-03-23

### 14:32 - Edit: src/agent/internal/collector.go
- プロジェクト: #my-project
- ブランチ: #branch/feature/new-ui

### 14:35 - Bash: go test ./...
- プロジェクト: #my-project
- ブランチ: #branch/feature/new-ui
\```

## 必要環境

- macOS / Linux
- Bash 3.2+
- [jq](https://jqlang.github.io/jq/)
- [Claude Code](https://claude.ai/code)

## インストール

\```bash
# 1. リポジトリをクローン
git clone https://github.com/10432mztn/claude-obsidian-logger.git
cd claude-obsidian-logger

# 2. インストール実行
bash install.sh
\```

インストール後、`~/.config/claude-obsidian-logger/config` で vault パスを設定:

\```bash
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"  # 変更する場合はここを編集
LOG_DIR="Claude Code"
\```

## アンインストール

\```bash
bash install.sh --uninstall
\```

## テスト

\```bash
bash tests/test_logger.sh
bash tests/test_install.sh
\```

## 仕組み

1. Claude Code が Edit / Write / MultiEdit / Bash ツールを実行するたびに `PostToolUse` hook が発火
2. `claude-obsidian-log.sh` が stdin から JSON ペイロードを受け取り
3. ツール名・対象ファイル/コマンドを抽出してデイリーノートに追記

詳細は [docs/design.md](docs/design.md) を参照。
```

- [ ] **Step 2: コミット**

```bash
git add README.md
git commit -m "docs: add README with setup instructions and output example"
```

---

## Task 8: 全テスト実行 & PR 作成

- [ ] **Step 1: 全テストを実行して PASS することを確認する**

```bash
bash tests/test_logger.sh && bash tests/test_install.sh
```

Expected: 両方とも `Results: N passed, 0 failed`

- [ ] **Step 2: ブランチを push する**

```bash
git push -u origin feature/implement-logger
```

- [ ] **Step 3: PR を作成する**

```bash
gh pr create \
  --title "feat: implement claude-obsidian-logger" \
  --body "$(cat <<'EOF'
## Summary

- `claude-obsidian-log.sh`: PostToolUse hook から呼ばれるメインロガー。stdin JSON をパースして Obsidian デイリーノートに追記。ファイルパスは `CLAUDE_PROJECT_DIR` からの相対パスで記録。
- `install.sh`: jq チェック・設定ファイル生成・シンボリックリンク作成・settings.json への hook 登録（冪等）。`--uninstall` で削除。
- `README.md`: セットアップ手順・出力例・仕組みを記載。
- `tests/`: bash スクリプトによる単体テスト。

## Test plan

- [ ] `bash tests/test_logger.sh` — Edit/Write/MultiEdit 相対パス記録、basename フォールバック、Bash 記録、120文字切り詰め、不正JSON exit 0、vault 不在 exit 0、git 外ブランチタグ省略、config 不在デフォルト値
- [ ] `bash tests/test_install.sh` — シンボリックリンク作成、設定ファイル作成、settings.json hook 追加、冪等性、アンインストール（リンク削除・hook 削除・config 保持）
- [ ] 実際の Claude Code セッションで Edit を実行し Obsidian デイリーノートに記録されることを確認

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---
