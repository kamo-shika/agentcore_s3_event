# Strands Agent 規約

## システムプロンプト

- 日本語で記述
- 定数として分離（`SYSTEM_PROMPT = """..."""`）

## ツール定義

- `@tool` デコレーターを使用
- docstringで機能を日本語で説明

## 例

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
    """
    ...
```
