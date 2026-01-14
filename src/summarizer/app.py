# =============================================================================
# AgentCore Runtime エントリポイント
# =============================================================================
# 概要:
#   BedrockAgentCoreAppを使用してAgentCore Runtimeのエントリポイントを定義
#   S3イベントからのペイロードを受け取り、ドキュメント要約処理を実行
#
# 処理フロー:
#   1. プロキシLambdaからHTTPリクエストを受信
#   2. ペイロードからS3バケット名とキーを取得
#   3. エージェントによる要約処理を実行
#   4. 結果をレスポンスとして返却
# =============================================================================

from __future__ import annotations

import logging
import os
from typing import Any

from bedrock_agentcore.runtime import BedrockAgentCoreApp

from .agent import process_document

# -----------------------------------------------------------------------------
# ロガーの設定
# -----------------------------------------------------------------------------
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# コンソールハンドラーを追加（CloudWatch Logsに出力）
handler = logging.StreamHandler()
handler.setFormatter(
    logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
)
logger.addHandler(handler)

# -----------------------------------------------------------------------------
# 環境変数から設定を読み込み
# -----------------------------------------------------------------------------
# AgentCoreMemoryのID（create_memory.pyで作成したもの）
AGENTCORE_MEMORY_ID = os.environ.get("AGENTCORE_MEMORY_ID", "")

# S3バケット名（Terraformで設定）
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")

# -----------------------------------------------------------------------------
# AgentCore Runtimeアプリケーションの初期化
# -----------------------------------------------------------------------------
app = BedrockAgentCoreApp()


@app.entrypoint
def invoke(payload: dict[str, Any]) -> dict[str, Any]:
    """
    AgentCore Runtimeのエントリポイント。

    プロキシLambdaから送信されたペイロードを受け取り、
    ドキュメント要約処理を実行する。

    Args:
        payload: リクエストペイロード
            - bucket: S3バケット名
            - key: S3オブジェクトキー（例: "alice/uploads/report.txt"）

    Returns:
        処理結果を含む辞書
            - success: 処理が成功したかどうか
            - summary_key: 保存された要約のS3キー
            - message: 処理結果メッセージ

    Example:
        >>> payload = {
        ...     "bucket": "my-bucket",
        ...     "key": "alice/uploads/report.txt"
        ... }
        >>> result = invoke(payload)
        >>> print(result)
        {
            "success": True,
            "summary_key": "alice/summaries/report.summary.txt",
            "message": "要約を正常に生成しました"
        }
    """
    logger.info(f"リクエスト受信: {payload}")

    # ペイロードからS3情報を取得
    bucket = payload.get("bucket", S3_BUCKET_NAME)
    key = payload.get("key", "")

    # 必須パラメータのバリデーション
    if not bucket:
        error_msg = "バケット名が指定されていません"
        logger.error(error_msg)
        return {"success": False, "message": error_msg}

    if not key:
        error_msg = "オブジェクトキーが指定されていません"
        logger.error(error_msg)
        return {"success": False, "message": error_msg}

    # S3キーからActor ID（ユーザーID）を抽出
    # キー構造: {user_id}/uploads/{filename}
    path_parts = key.split("/")
    if len(path_parts) < 3:
        error_msg = f"無効なS3キー形式です: {key}（期待: {{user_id}}/uploads/{{filename}}）"
        logger.error(error_msg)
        return {"success": False, "message": error_msg}

    actor_id = path_parts[0]
    filename = path_parts[-1]

    logger.info(f"処理開始: actor_id={actor_id}, filename={filename}")

    try:
        # ドキュメント要約処理を実行
        result = process_document(
            bucket=bucket,
            key=key,
            actor_id=actor_id,
            memory_id=AGENTCORE_MEMORY_ID,
        )

        logger.info(f"処理完了: {result}")
        return result

    except Exception as e:
        # エラーハンドリング
        error_msg = f"要約処理中にエラーが発生しました: {e}"
        logger.exception(error_msg)
        return {"success": False, "message": error_msg}


# -----------------------------------------------------------------------------
# ヘルスチェックエンドポイント（オプション）
# -----------------------------------------------------------------------------
@app.route("/ping")
def health_check() -> dict[str, str]:
    """
    ヘルスチェック用エンドポイント。

    Returns:
        ステータスを含む辞書
    """
    return {"status": "healthy"}


# -----------------------------------------------------------------------------
# メイン実行
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    # ローカルテスト用
    # 本番環境ではAgentCore Runtimeが自動的に起動する
    logger.info("AgentCore Runtime アプリケーションを起動します...")
    logger.info(f"AGENTCORE_MEMORY_ID: {AGENTCORE_MEMORY_ID}")
    logger.info(f"S3_BUCKET_NAME: {S3_BUCKET_NAME}")
    app.run()
