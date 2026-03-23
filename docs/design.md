# Obsidian Progress Logger — Design Spec

## Overview

Claude Code の hook 機能を利用して、作業進捗を Obsidian のデイリーノートにリアルタイム記録するシェルスクリプトツール。

## Goals

- アクション単位（ファイル編集、コマンド実行、ファイル作成）でリアルタイム記録
- トークン消費ゼロ（hook はモデル外で実行される）
- プロジェクト名・ブランチ名をタグとして自動付与
- Obsidian のタグ検索でプロジェクト横断・ブランチ横断の振り返りが可能
- 別 PC でも clone + install.sh で即セットアップ可能

## Non-Goals

- コード差分やプロンプト内容の記録（プライバシー考慮）
- Obsidian vault の自動 Git commit/push（ユーザー運用に任せる）
- セッションサマリの自動生成（トークン消費が発生するため）

## Architecture

```
Claude Code
  │
  ├─ PostToolUse hook (Edit/Write/Bash/MultiEdit)
  │     │
  │     └─ claude-obsidian-log.sh
  │           │
  │           ├─ stdin から JSON ペイロードを読み取り
  │           ├─ jq でツール名・入力を抽出
  │           ├─ git branch / $CLAUDE_PROJECT_DIR でタグ取得
  │           └─ Obsidian vault にマークダウン追記
  │
  └─ ~/Documents/Obsidian Vault/Claude Code/YYYY-MM-DD.md
```

## Repository Structure

```
~/dev/claude-obsidian-logger/
├── README.md
├── docs/
│   └── design.md              ← この設計ドキュメント
├── claude-obsidian-log.sh     ← メインスクリプト
└── install.sh                 ← セットアップ / アンインストールスクリプト
```

## Components

### 1. Shell Script: `claude-obsidian-log.sh`

Hook から呼び出されるメインスクリプト。install.sh により `~/.local/bin/` にシンボリックリンクされる。

**入力**: Claude Code hook が **stdin に JSON ペイロード** を渡す
- `tool_name` — ツール名（Edit, Write, MultiEdit, Bash）
- `tool_input` — ツールの入力（オブジェクト）

```bash
# stdin JSON の例
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/Users/hokan_124/dev/project/src/main.ts",
    "old_string": "...",
    "new_string": "..."
  }
}
```

**処理**:
1. stdin から JSON を読み取り、jq でパース
2. 今日の日付で出力ファイルパスを決定
3. ファイルが存在しなければヘッダ付きで新規作成
4. ツール種別に応じて対象情報を抽出
5. タイムスタンプ + ツール名 + 対象 + タグを整形して追記

**エラーハンドリング**: すべてのエラーで `exit 0` する（非ゼロ終了は Claude Code の動作を妨げる可能性がある）。エラーは stderr に出力するが、処理は止めない。

**出力**: Obsidian vault 内のデイリーノートに追記

### 2. Hook Configuration

install.sh が `~/.claude/settings.json` に以下を追加:

```jsonc
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/claude-obsidian-log.sh"
          }
        ]
      }
    ]
  }
}
```

グローバル設定に登録するため、全プロジェクトで有効。

### 3. Output Format

ファイル: `~/Documents/Obsidian Vault/Claude Code/YYYY-MM-DD.md`

```markdown
# 2026-03-23

### 14:32 - Edit: src/agent/internal/collector.go
- プロジェクト: #hokan-ai-metrics
- ブランチ: #branch/feature/queue-flush

### 14:35 - Bash: go test ./...
- プロジェクト: #hokan-ai-metrics
- ブランチ: #branch/feature/queue-flush

### 14:40 - Write: src/new-file.ts
- プロジェクト: #hokan-ai-metrics
- ブランチ: #branch/feature/queue-flush
```

### 4. install.sh

セットアップスクリプト。`install.sh` と `install.sh --uninstall` の2モードで動作。

**インストール**:
1. `jq` の存在確認（なければエラー終了しインストール案内を表示）
2. 設定ファイル (`~/.config/claude-obsidian-logger/config`) を作成
   - `OBSIDIAN_VAULT_PATH` — vault のパス（デフォルト: `~/Documents/Obsidian Vault`）
   - `LOG_DIR` — vault 内の出力フォルダ名（デフォルト: `Claude Code`）
3. `~/.local/bin/` ディレクトリを作成（なければ）
4. `~/.local/bin/claude-obsidian-log.sh` にシンボリックリンクを作成
5. `~/.claude/settings.json` に hook 設定を jq でマージ

**settings.json マージ戦略**:
- `hooks` キーが存在しなければ作成
- `hooks.PostToolUse` が存在しなければ作成
- 既に同じ matcher のエントリがあればスキップ（冪等）
- 他のキー（env, model, plugins 等）は一切変更しない

**アンインストール** (`install.sh --uninstall`):
1. シンボリックリンクを削除
2. settings.json から該当 hook エントリを削除
3. 設定ファイルは残す（ユーザーデータのため）

## Tag Strategy

| タグ | 取得方法 | 例 |
|------|----------|-----|
| プロジェクト名 | `$CLAUDE_PROJECT_DIR` の basename、またはフォールバックで `basename $(pwd)` | `#hokan-ai-metrics` |
| ブランチ名 | `git branch --show-current`（git リポジトリ外では省略） | `#branch/feature/queue-flush` |

## Tool Input Parsing

各ツールから記録する情報（すべて stdin JSON から jq で抽出）:

| ツール | 抽出する情報 | jq クエリ |
|--------|-------------|-----------|
| Edit | ファイルパス | `.tool_input.file_path` |
| Write | ファイルパス | `.tool_input.file_path` |
| MultiEdit | ファイルパス | `.tool_input.file_path` |
| Bash | コマンド（先頭120文字に切り詰め） | `.tool_input.command` |

Bash コマンドは長くなりうるため、120文字で切り詰めて `...` を付与する。

## Configuration

`~/.config/claude-obsidian-logger/config`:

```bash
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"
LOG_DIR="Claude Code"
```

別 PC では vault のパスが異なる可能性があるため、設定ファイルで外出し。

## Error Handling

- すべてのエラーで **exit 0** を返す（hook の非ゼロ終了は Claude Code に影響しうるため）
- vault ディレクトリが存在しない場合: stderr に警告を出して exit 0
- config ファイルが存在しない場合: デフォルト値を使用
- jq が存在しない場合: stderr に警告を出して exit 0
- git リポジトリ外の場合: ブランチタグを省略して記録は続行
- stdin JSON が不正な場合: stderr に警告を出して exit 0

## Performance Considerations

- スクリプトは追記のみ（`>>` リダイレクト）で I/O 最小
- 小さい書き込みの `>>` は一般的なファイルシステムでアトミック（並行書き込みは安全と想定）
- Git コマンド（branch 取得）は軽量
- JSON パースは最小限（1フィールドのみ）
- hook がブロッキングのため、処理は 100ms 以内に収める想定
- タイムゾーンはシステムのローカルタイムゾーンを使用

## Testing

- スクリプト単体テスト: stdin に JSON をパイプして実行、出力ファイルの内容を検証
- 統合テスト: Claude Code で実際に Edit/Write/Bash を実行して記録を確認
