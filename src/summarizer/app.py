# =============================================================================
# AgentCore Runtime エントリポイント（非同期実行版）
# =============================================================================
# 概要:
#   BedrockAgentCoreAppを使用してAgentCore Runtimeのエントリポイントを定義
#   S3イベントからのペイロードを受け取り、非同期でドキュメント要約処理を実行
#
# 処理フロー:
#   1. プロキシLambdaからHTTPリクエストを受信
#   2. ペイロードからS3バケット名とキーを取得
#   3. 即座にACKレスポンスを返却
#   4. バックグラウンドでエージェントによる要約処理を実行
#   5. 処理完了後、S3に結果を保存
#
# 非同期実行の利点:
#   - Lambdaのタイムアウト（30秒）を超える長時間処理に対応
#   - 最大8時間の処理時間をサポート
#   - セッション再利用でコールドスタート削減
# =============================================================================

from __future__ import annotations

import logging
import os
import threading
from typing import Any

from bedrock_agentcore.runtime import BedrockAgentCoreApp

from .agent import process_document

# -----------------------------------------------------------------------------
# ロガーの設定
# -----------------------------------------------------------------------------
# ルートロガーを設定して全てのログを確実に出力
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
    force=True,  # 既存の設定を上書き
)

# このモジュール用のロガー
logger = logging.getLogger(__name__)

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
logger.info("=" * 60)
logger.info("AgentCore Runtime アプリケーション初期化開始")
logger.info(f"AGENTCORE_MEMORY_ID: {AGENTCORE_MEMORY_ID or '(未設定)'}")
logger.info(f"S3_BUCKET_NAME: {S3_BUCKET_NAME or '(未設定)'}")
logger.info("=" * 60)

app = BedrockAgentCoreApp()
logger.info("BedrockAgentCoreApp 初期化完了")


def _run_background_process(
    task_id: str,
    bucket: str,
    key: str,
    actor_id: str,
    memory_id: str,
) -> None:
    """
    バックグラウンドでドキュメント処理を実行する。

    処理完了後、非同期タスクを完了としてマークする。
    この関数はスレッドで実行されるため、メインスレッドをブロックしない。

    Args:
        task_id: 非同期タスクのID
        bucket: S3バケット名
        key: S3オブジェクトキー
        actor_id: ユーザーID
        memory_id: AgentCoreMemoryのID
    """
    logger.info(f"バックグラウンド処理開始: task_id={task_id}, key={key}")

    try:
        # ドキュメント要約処理を実行
        result = process_document(
            bucket=bucket,
            key=key,
            actor_id=actor_id,
            memory_id=memory_id,
        )

        if result.get("success"):
            logger.info(f"バックグラウンド処理完了: task_id={task_id}, result={result}")
        else:
            logger.error(f"バックグラウンド処理失敗: task_id={task_id}, result={result}")

    except Exception as e:
        logger.exception(f"バックグラウンド処理中に予期しないエラー: task_id={task_id}, error={e}")

    finally:
        # 非同期タスクを完了としてマーク
        # これにより、Pingステータスが HealthyBusy から Healthy に戻る
        app.complete_async_task(task_id)
        logger.info(f"非同期タスク完了マーク: task_id={task_id}")


@app.entrypoint
def invoke(payload: dict[str, Any]) -> dict[str, Any]:
    """
    AgentCore Runtimeのエントリポイント（非同期版）。

    プロキシLambdaから送信されたペイロードを受け取り、
    即座にACKレスポンスを返却した後、バックグラウンドでドキュメント要約処理を実行する。

    この非同期実行により、Lambdaのタイムアウトを超える長時間処理にも対応可能。

    Args:
        payload: リクエストペイロード
            - bucket: S3バケット名
            - key: S3オブジェクトキー（例: "alice/uploads/report.txt"）

    Returns:
        処理受付結果を含む辞書
            - status: "accepted"（受付成功）または "error"（バリデーションエラー）
            - task_id: 非同期タスクのID（受付成功時）
            - message: 結果メッセージ

    Example:
        >>> payload = {
        ...     "bucket": "my-bucket",
        ...     "key": "alice/uploads/report.txt"
        ... }
        >>> result = invoke(payload)
        >>> print(result)
        {
            "status": "accepted",
            "task_id": "abc123-def456",
            "message": "処理をバックグラウンドで開始しました"
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
        return {"status": "error", "message": error_msg}

    if not key:
        error_msg = "オブジェクトキーが指定されていません"
        logger.error(error_msg)
        return {"status": "error", "message": error_msg}

    # S3キーからActor ID（ユーザーID）を抽出
    # キー構造: {user_id}/uploads/{filename}
    path_parts = key.split("/")
    if len(path_parts) < 3:
        error_msg = f"無効なS3キー形式です: {key}（期待: {{user_id}}/uploads/{{filename}}）"
        logger.error(error_msg)
        return {"status": "error", "message": error_msg}

    actor_id = path_parts[0]
    filename = path_parts[-1]

    logger.info(f"処理受付: actor_id={actor_id}, filename={filename}")

    # 非同期タスクを登録
    # add_async_task() により、Pingステータスが HealthyBusy になる
    task_id = app.add_async_task(
        "document_processing",
        {"bucket": bucket, "key": key, "actor_id": actor_id},
    )
    logger.info(f"非同期タスク登録: task_id={task_id}")

    # バックグラウンドスレッドで処理を実行
    # daemon=True により、メインプロセス終了時にスレッドも終了する
    thread = threading.Thread(
        target=_run_background_process,
        args=(task_id, bucket, key, actor_id, AGENTCORE_MEMORY_ID),
        daemon=True,
    )
    thread.start()

    # 即座にACKレスポンスを返却
    # 処理はバックグラウンドで継続される
    return {
        "status": "accepted",
        "task_id": task_id,
        "message": "処理をバックグラウンドで開始しました",
    }


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
