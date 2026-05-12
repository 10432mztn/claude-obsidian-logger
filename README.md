# claude-obsidian-logger

Claude Code の [hook 機能](https://docs.anthropic.com/en/docs/claude-code/hooks) を使って、作業進捗を Obsidian のデイリーノートにリアルタイム記録するシェルスクリプトツール。

## 特徴

- **ナラティブ重視** — ユーザー発言・ツール操作を1枚のデイリーノートに集約
- **トークン消費ゼロ** — hook はモデル外で動作。LLM を呼び出さない
- **タグ自動付与** — git root を逆引きしてプロジェクト名・ブランチ名を Obsidian タグ化
- **ノイズフィルタ** — `ls` `cat` `head` 等の読み取り系コマンドは記録しない（`SKIP_BASH_PATTERN` で調整可）
- **要約は対話セッションで** — Stop hook は機械統計のみ記録し、「📋 今日の総括 / 🎯 明日やること」は slash command `/daily-rollup` で対話 Claude に生成させる（hook 内で `claude -p` を呼ぶと認証パスが分離して失敗するため）

## 出力例

`~/Documents/Obsidian Vault/Claude Code/2026-05-12.md`:

```markdown
# 2026-05-12

<!-- ROLLUP:START -->
## 📋 今日の総括
- Clipy のスニペットを 4 カテゴリに再編、Obsidian Vault を ~/life に一本化
- claude-obsidian-logger のナラティブ改修を PR #2 として提出
- Ghostty config を arm64 強制起動の除去 + scrollback 拡大で最適化

## 🎯 明日やること
- [ ] PR #2 のレビュー対応・マージ
- [ ] hokan-ai-metrics の supateam 機能取込 Issue 群を優先付け
- [ ] Karabiner / Rectangle の最適化（ペンディング）

_最終更新: 23:45_
<!-- ROLLUP:END -->

## 🗣 10:32 — #dev
> Clipyのスニペット整理したい

- **10:33** ⚡ Bash — List installed apps _(#dev)_
- **10:35** 📝 Write — snippets_reorganized.xml _(#dev)_

---
## 11:12 セッションサマリー #claude-obsidian-logger

## やったこと
- PR #1 をマージ、ローカルの README 整形 + session-summary.sh を取込
- ロガーのナラティブ化方針を決定

## 次のステップ
- description フィールド対応、UserPromptSubmit hook 実装
```

## 必要環境

- macOS / Linux
- Bash 3.2+
- [jq](https://jqlang.github.io/jq/)
- [Claude Code](https://claude.ai/code)

## インストール

### 1. jq をインストール

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt install jq
```

### 2. リポジトリをクローンしてインストール

```bash
git clone https://github.com/10432mztn/claude-obsidian-logger.git
cd claude-obsidian-logger
bash install.sh
```

### 3. vault パスを設定

`~/.config/claude-obsidian-logger/config` を編集:

```bash
OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian Vault"  # 実際の vault パスに変更
LOG_DIR="Claude Code"
```

### 4. Obsidian の設定

特別なプラグインは不要。Obsidian が上記の vault を開いていれば、`Claude Code/` フォルダにデイリーノートが自動作成されます。

> **vault パスの確認方法:** Obsidian → 設定（⚙️）→ vault → 「vault を開く場所」に表示されるパスを `OBSIDIAN_VAULT_PATH` に設定してください。

### 5. Claude Code を再起動

hook を有効化するため、Claude Code を再起動してください。

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
