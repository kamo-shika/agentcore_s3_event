# コーディング規約・実装ルール

## 概要

このドキュメントは、S3イベント駆動 Strands Agents サンプルプロジェクトのコーディング規約をまとめたものです。

---

## 1. 全般

### 1.1 言語設定
- **コメント**: 日本語で記述
- **docstring**: 日本語で記述
- **変数名・関数名**: 英語（スネークケース）
- **クラス名**: 英語（パスカルケース）

### 1.2 コメント方針
- **すべての関数**: docstringを必須とする
- **複雑なロジック**: 処理の意図を日本語コメントで説明
- **マジックナンバー禁止**: 定数として定義し、意味をコメントで説明
- **TODO/FIXME**: 日本語で記述、担当者名を記載

```python
# 良い例
def calculate_timeout(file_size: int) -> int:
    """
    ファイルサイズに基づいてタイムアウト値を計算する。

    Args:
        file_size: ファイルサイズ（バイト）

    Returns:
        タイムアウト値（秒）
    """
    # 1MBあたり10秒 + 基本タイムアウト30秒
    BASE_TIMEOUT_SECONDS = 30
    SECONDS_PER_MB = 10

    return BASE_TIMEOUT_SECONDS + (file_size // (1024 * 1024)) * SECONDS_PER_MB
```

---

## 2. Python コード規約

### 2.1 スタイル
- **フォーマッター**: ruff format
- **リンター**: ruff check
- **行の長さ**: 最大100文字
- **インデント**: スペース4つ

### 2.2 型ヒント
- すべての関数に型ヒントを付ける
- `from __future__ import annotations` を使用
- 複雑な型は `TypeAlias` で定義

```python
from __future__ import annotations
from typing import TypeAlias

# 型エイリアスの定義
S3EventRecord: TypeAlias = dict[str, any]
SummaryResult: TypeAlias = dict[str, str]
```

### 2.3 インポート順序
1. 標準ライブラリ
2. サードパーティライブラリ
3. ローカルモジュール

```python
# 標準ライブラリ
import os
import json
from datetime import datetime

# サードパーティ
import boto3
from strands import Agent

# ローカル
from .tools import read_text_file, save_summary
```

### 2.4 エラーハンドリング
- 具体的な例外をキャッチする（`Exception` は避ける）
- エラーメッセージは日本語で記述
- ログ出力を必ず行う

```python
try:
    content = s3_client.get_object(Bucket=bucket, Key=key)
except s3_client.exceptions.NoSuchKey:
    # ファイルが存在しない場合のエラーハンドリング
    logger.error(f"ファイルが見つかりません: s3://{bucket}/{key}")
    raise FileNotFoundError(f"S3オブジェクトが存在しません: {key}")
```

---

## 3. ログ出力規約

### 3.1 ログレベル
| レベル | 用途 |
|--------|------|
| DEBUG | 開発時のデバッグ情報 |
| INFO | 正常な処理の進行状況 |
| WARNING | 想定内の問題（処理は継続） |
| ERROR | エラー発生（処理失敗） |

### 3.2 ログフォーマット
```python
import logging

# ロガーの設定
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ログ出力例
logger.info(f"処理開始: bucket={bucket}, key={key}")
logger.info(f"要約生成完了: 文字数={len(summary)}")
logger.error(f"AgentCoreMemory保存失敗: {error}")
```

---

## 4. Strands Agent 実装規約

### 4.1 システムプロンプト
- 日本語で記述
- 役割、能力、制約を明確に定義
- 定数として分離

```python
SUMMARIZER_SYSTEM_PROMPT = """
あなたは文書要約アシスタントです。

## 役割
- アップロードされたテキストファイルを読み取り、要約を生成します
- 過去の関連情報を参照して、文脈を踏まえた要約を作成します

## 制約
- 要約は日本語で300文字以内
- 事実に基づいた内容のみ記載
- 推測や解釈は含めない
"""
```

### 4.2 ツール定義
- `@tool` デコレーターを使用
- docstringで機能を説明
- 引数・戻り値の型を明示

```python
from strands import tool

@tool
def read_text_file(bucket: str, key: str) -> str:
    """
    S3からテキストファイルを読み取る。

    Args:
        bucket: S3バケット名
        key: S3オブジェクトキー

    Returns:
        ファイルの内容（UTF-8テキスト）

    Raises:
        FileNotFoundError: ファイルが存在しない場合
    """
    # 実装...
```

---

## 5. Terraform 規約

### 5.1 命名規則
- リソース名: `{project}_{resource_type}_{purpose}`
- 変数名: スネークケース
- タグ: すべてのリソースに `Project`, `Environment` タグを付与

```hcl
resource "aws_s3_bucket" "doc_summarizer_input" {
  bucket = "${var.project_name}-input-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    # 日本語コメント: ドキュメントアップロード用バケット
  }
}
```

### 5.2 ファイル構成
| ファイル | 内容 |
|----------|------|
| `main.tf` | プロバイダー設定、データソース |
| `variables.tf` | 変数定義（説明は日本語） |
| `outputs.tf` | 出力値定義 |
| `s3.tf` | S3関連リソース |
| `lambda.tf` | Lambda関連リソース |
| `iam.tf` | IAMロール・ポリシー |

### 5.3 変数定義
```hcl
variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "プロジェクト名（リソース名のプレフィックスに使用）"
  type        = string
  default     = "strands-doc-summarizer"
}
```

---

## 6. Docker 規約

### 6.1 ベースイメージ
- uv公式イメージを使用
- ARM64アーキテクチャ指定
- Python 3.12

### 6.2 Dockerfile構成
```dockerfile
# ベースイメージ（ARM64 + Python 3.12）
FROM --platform=linux/arm64 ghcr.io/astral-sh/uv:python3.12-bookworm-slim

# 作業ディレクトリ
WORKDIR /app

# 依存関係のインストール（キャッシュ活用のため先にコピー）
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-cache

# アプリケーションコードのコピー
COPY src/ ./src/

# ポート公開
EXPOSE 8080

# 起動コマンド
CMD ["uv", "run", "python", "-m", "summarizer.app"]
```

---

## 7. テスト規約

### 7.1 テストファイル命名
- `test_{module_name}.py`
- テスト関数: `test_{機能}_{条件}_{期待結果}`

```python
def test_read_text_file_存在するファイル_内容を返す():
    """存在するファイルを読み取った場合、内容が返されること"""
    # テスト実装...

def test_read_text_file_存在しないファイル_例外発生():
    """存在しないファイルを読み取った場合、FileNotFoundErrorが発生すること"""
    # テスト実装...
```

### 7.2 モック使用
- AWS関連はすべてモック化
- `moto` ライブラリを使用

---

## 8. Git規約

### 8.1 コミットメッセージ
```
<type>: <日本語での説明>

<詳細な説明（任意）>
```

**type一覧:**
- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメント
- `refactor`: リファクタリング
- `test`: テスト追加・修正
- `chore`: その他

**例:**
```
feat: AgentCore Runtime用のエントリポイントを実装

- BedrockAgentCoreAppを使用したハンドラー
- S3イベントからのペイロード処理
```

---

## 9. セキュリティ規約

### 9.1 禁止事項
- ハードコードされた認証情報
- ログへの機密情報出力
- 過剰なIAM権限

### 9.2 推奨事項
- 環境変数での設定管理
- 最小権限の原則
- シークレットはAWS Secrets Managerを使用

---

## 10. 参照ドキュメント

- [Strands Agents ドキュメント](https://strandsagents.com/)
- [Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock/)
- [uv ドキュメント](https://docs.astral.sh/uv/)
