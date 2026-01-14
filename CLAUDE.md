# Project Rules for Claude Code

このプロジェクトは S3イベント駆動の Strands Agents ドキュメント要約システムです。

## 言語設定

- **コメント・docstring**: 必ず日本語で記述
- **変数名・関数名**: 英語（スネークケース）
- **クラス名**: 英語（パスカルケース）
- **コミットメッセージ**: 日本語

## 禁止事項

- ハードコードされた認証情報
- ログへの機密情報出力
- `Exception` での広範なキャッチ
- 型ヒントなしの関数定義
- 英語のみのコメント

## ファイル構成

```
src/summarizer/     # メインアプリケーション
lambda/             # プロキシLambda
terraform/          # インフラ定義（AgentCoreMemory含む）
scripts/            # ビルド・デプロイスクリプト
.claude/rules/      # モジュール化されたルール
```

## 詳細ルール

詳細なルールは `.claude/rules/` ディレクトリを参照：

| ファイル | 内容 |
|---------|------|
| `workflow.md` | Claude Code対応、git worktree運用 |
| `python.md` | Pythonコード規約、ログ出力 |
| `terraform.md` | Terraform命名規則、ファイル構成 |
| `strands.md` | Strands Agentツール定義 |
