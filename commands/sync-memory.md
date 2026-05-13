# Sync Memory

`~/life/claude-sessions/$ARGUMENTS.md`（引数省略時は今日 `date +%Y-%m-%d`）のデイリーロールアップから、**memory に昇格すべき学び・決定事項を抽出**し、ユーザー承認のもと `~/.claude/projects/-Users-hokan-124-dev/memory/` に新規 memory ファイルを作成・`MEMORY.md` の index も更新する。

## 重要原則

- **必ず提案フェーズで止まる**。検出した候補をユーザーに見せて承認を取ってから書き込む
- **承認なしに直接ファイルを書かない**（destructive と見なす）
- **既存 memory との重複**を必ずチェック（同一内容/類似テーマがあれば「既存を更新」を提案）
- **`auto-memory` の Skill 規約に準拠**: 各ファイルは `name` / `description` / `metadata.type` の frontmatter を持ち、`feedback` / `project` 型は本文に **Why:** と **How to apply:** を含めること。`MEMORY.md` は 1 行 150 文字以内のインデックス。

## ステップ

1. **対象ファイルを Read**:
   - 引数 `$ARGUMENTS` があればその日付、無ければ今日（`date +%Y-%m-%d`）
   - パス: `~/life/claude-sessions/YYYY-MM-DD.md`
   - 引数に `--last-week` が渡されたら、過去 7 日分を全部読む

2. **既存 memory を Read**:
   - `~/.claude/projects/-Users-hokan-124-dev/memory/MEMORY.md`
   - 重複検出のため index から既存トピック一覧を把握

3. **抽出シグナルでスキャン**:
   - **明示的なメモリ化意図**: 「memory に追加」「memory 化」「[[xxx]] 追加」「決定事項として記録」
   - **ルール・規約**: 「禁止」「必ず」「絶対」「〜してはいけない」「〜すべき」を含む発言、特に Claude の応答ではなくユーザー発言由来
   - **判明した事実・参照**: 「〜と判明」「正体は〜」「公式ドキュメント」「API は〜」
   - **失敗からの学び**: 「事件」「壊れた」「詰んだ」「ハマった」+ 原因究明
   - **方針合意・採用判断**: 「やめる」「採用」「これでいく」「方針合意」
   - **ツール・サービスの場所**: URL / リポジトリパス / ダッシュボード等の reference 候補

4. **抽出結果をユーザーに提示**:
   - 1 件ごとに以下を表示:
     ```
     提案 N: <短いタイトル>
     - type: user|feedback|project|reference
     - description: <1 行>
     - 本文（プレビュー）:
       <2-5 行>
     - 既存重複: <重複候補 memory 名 or "なし">
     - 根拠（ロールアップ該当行）:
       > <該当行>
     ```
   - 個別または全件で「採用 / スキップ / 修正してから採用」を `AskUserQuestion` で聞く

5. **承認分を書き込む**:
   - 各メモリのファイル名は `{type}_{kebab-case-slug}.md`
   - frontmatter フォーマット:
     ```yaml
     ---
     name: {slug}
     description: {one-line specific description}
     metadata:
       type: {user|feedback|project|reference}
     ---
     ```
   - 本文（feedback/project は構造化）:
     - リード文（ルール／事実）
     - **Why:** <なぜそうするか／背景となる incident・制約>
     - **How to apply:** <いつ／どう適用するか>
     - 関連: `[[other-memory-name]]` で他 memory にリンク
   - `~/.claude/projects/-Users-hokan-124-dev/memory/MEMORY.md` の末尾に index 行を追加:
     ```
     - [{filename}]({filename}) — {description}
     ```

6. **既存 memory を更新する場合**:
   - 重複検出時、ユーザーが「既存を更新」を選んだら、対象 memory ファイルを Read → 内容統合 → Write
   - `MEMORY.md` の該当行の description も更新

7. **完了報告**:
   - 新規追加 N 件、既存更新 M 件、スキップ K 件
   - 追加した memory のファイル名一覧

## 抽出の判断基準（重要）

### 採用すべきもの

- 「次回もこの判断を踏襲したい」一般化できるルール
- 過去 incident からの教訓（具体名・原因・対策セット）
- 外部システムの **存在場所**（リポジトリ / ダッシュボード / API）
- ユーザーの **役割・専門性・進め方の好み**（user 型）

### 採用すべきでないもの

- 「今日 X を編集した」のような操作ログ（コードに残ってる）
- 一度きりの bug 修正手順（commit message が役割を果たす）
- 既に CLAUDE.md / AGENTS.md にあるもの
- ephemeral な状態（今のブランチ／今の作業中タスク）
- 機密情報（パスワード、ExternalId、秘密鍵） — **絶対に書かない**

## 引数

- なし: 今日のデイリーロールアップから抽出
- `YYYY-MM-DD`: 指定日のロールアップから抽出
- `--last-week`: 過去 7 日分のロールアップを横断スキャン（週次の memory promotion で使う）

## 出力例

```
🔍 ~/life/claude-sessions/2026-05-12.md からスキャンしました。

提案 1: feedback_sandbox_naming
- type: feedback
- description: Snowflake sandbox schema 名は Snowflake ユーザー名と完全一致（略称禁止）
- 本文プレビュー:
  Snowflake sandbox schema 名は Snowflake ユーザー名と完全一致させる（略称禁止）。
  **Why:** 他人事に見えると運用責任が曖昧化するため。「TMIZUTANI」のような略称
  だと、誰が責任を持つ sandbox なのか他者から判断しにくい。
  **How to apply:** sandbox 作成・改名時。Terraform module 側でも略称を受け付けない。
- 既存重複: なし
- 根拠:
  > 他人事なのでTOSHIMITSUMIZUTANIのほうが良さそう。アカウント名と一緒

採用しますか？ [全件採用 / 個別選択 / 全件スキップ]
```

## 関連 slash command

- `/daily-rollup`: 本コマンドの入力源（デイリーロールアップ）を生成
- 将来: `/weekly-rollup` — 週次まとめ。`/sync-memory --last-week` と組み合わせて週末バッチに
