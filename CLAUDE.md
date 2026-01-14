# Project Rules for Claude Code

このプロジェクトは S3イベント駆動の Strands Agents ドキュメント要約システムです。

## 言語設定

- **コメント・docstring**: 必ず日本語で記述
- **変数名・関数名**: 英語（スネークケース）
- **クラス名**: 英語（パスカルケース）
- **コミットメッセージ**: 日本語

## Pythonコード規約

### 必須事項
- すべての関数に日本語docstringを付ける
- すべての関数に型ヒントを付ける
- `from __future__ import annotations` を使用
- 行の最大長は100文字

### インポート順序
1. 標準ライブラリ
2. サードパーティ（boto3, strands等）
3. ローカルモジュール

### エラーハンドリング
- 具体的な例外をキャッチする（`Exception` は避ける）
- エラーメッセージは日本語
- 必ずlogger出力を行う

## ログ出力

```python
import logging
logger = logging.getLogger(__name__)

# 例
logger.info(f"処理開始: bucket={bucket}, key={key}")
logger.error(f"ファイルが見つかりません: {path}")
```

## Strands Agent

### システムプロンプト
- 日本語で記述
- 定数として分離（`SYSTEM_PROMPT = """..."""`）

### ツール定義
- `@tool` デコレーターを使用
- docstringで機能を日本語で説明

## Terraform

### 命名規則
- リソース名: `{project}_{resource_type}_{purpose}`
- すべてのリソースに `Project`, `Environment` タグを付与

### コメント
- HCLファイル内のコメントも日本語で記述

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
terraform/          # インフラ定義
setup/              # 初期セットアップスクリプト
scripts/            # ビルド・デプロイスクリプト
```

## パッケージ管理

- `uv` を使用（pip/poetry ではない）
- 依存関係は `pyproject.toml` で管理
