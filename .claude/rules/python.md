# Python コード規約

## 必須事項

- すべての関数に日本語docstringを付ける
- すべての関数に型ヒントを付ける
- `from __future__ import annotations` を使用
- 行の最大長は100文字

## インポート順序

1. 標準ライブラリ
2. サードパーティ（boto3, strands等）
3. ローカルモジュール

## エラーハンドリング

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

## パッケージ管理

- `uv` を使用（pip/poetry ではない）
- 依存関係は `pyproject.toml` で管理
