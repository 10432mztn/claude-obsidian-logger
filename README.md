# claude-obsidian-logger

Claude Code の [hook 機能](https://docs.anthropic.com/en/docs/claude-code/hooks) を使って、作業進捗を Obsidian のデイリーノートにリアルタイム記録するシェルスクリプトツール。

## 特徴

- **トークン消費ゼロ** — hook はモデル外で実行されるため
- **アクション単位で記録** — Edit / Write / MultiEdit / Bash ごとに自動追記
- **タグ自動付与** — プロジェクト名・ブランチ名を Obsidian タグとして記録
- **プロジェクト横断検索** — タグ検索で全プロジェクトの作業履歴を横断参照

## 出力例

`~/Documents/Obsidian Vault/Claude Code/2026-03-23.md`:

```markdown
# 2026-03-23

### 14:32 - Edit: src/agent/internal/collector.go
- プロジェクト: #my-project
- ブランチ: #branch/feature/new-ui

### 14:35 - Bash: go test ./...
- プロジェクト: #my-project
- ブランチ: #branch/feature/new-ui
```

## 必要環境

- macOS / Linux
- Bash 3.2+
- [jq](https://jqlang.github.io/jq/)
- [Claude Code](https://claude.ai/code)

## インストール

```bash
# 1. リポジトリをクローン
git clone https://github.com/10432mztn/claude-obsidian-logger.git
cd claude-obsidian-logger

# 2. インストール実行
bash install.sh
```

インストール後、`~/.config/claude-obsidian-logger/config` で vault パスを設定:

```bash
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"  # 変更する場合はここを編集
LOG_DIR="Claude Code"
```

## アンインストール

```bash
bash install.sh --uninstall
```

## テスト

```bash
bash tests/test_logger.sh
bash tests/test_install.sh
```

## 仕組み

1. Claude Code が Edit / Write / MultiEdit / Bash ツールを実行するたびに `PostToolUse` hook が発火
2. `claude-obsidian-log.sh` が stdin から JSON ペイロードを受け取り
3. ツール名・対象ファイル/コマンドを抽出してデイリーノートに追記

詳細は [docs/design.md](docs/design.md) を参照。
