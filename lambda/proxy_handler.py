# =============================================================================
# プロキシLambda ハンドラー（非同期実行対応版）
# =============================================================================
# 概要:
#   S3イベント通知を受け取り、AgentCore Runtimeに非同期処理をリクエストする
#   薄いプロキシレイヤーとして機能
#
# 処理フロー:
#   1. S3イベント通知を受信
#   2. イベントからバケット名とオブジェクトキーを抽出
#   3. ファイル拡張子をチェック（.txt, .md のみ処理）
#   4. AgentCore Runtimeに非同期処理をリクエスト（即座にACKを受信）
#   5. 処理受付結果をレスポンスとして返却
#
# 非同期実行の利点:
#   - Lambdaのタイムアウト（30秒）を超える長時間処理に対応
#   - 即座にレスポンスを受け取り、Lambdaを短時間で終了
#   - 実際の処理はAgentCore Runtimeでバックグラウンド実行
#
# 環境変数:
#   - AGENTCORE_RUNTIME_ENDPOINT: AgentCore RuntimeのエンドポイントURL
#   - AGENTCORE_RUNTIME_ID: AgentCore RuntimeのID
# =============================================================================

from __future__ import annotations

import json
import logging
import os
import urllib.parse
from typing import Any

import boto3
from botocore.exceptions import ClientError

# -----------------------------------------------------------------------------
# ロガーの設定
# -----------------------------------------------------------------------------
# Lambdaでは標準のloggingモジュールを使用
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# -----------------------------------------------------------------------------
# 環境変数から設定を読み込み
# -----------------------------------------------------------------------------
# AgentCore RuntimeのエンドポイントURL
# 例: "https://xxx.bedrock-agentcore.us-east-1.amazonaws.com"
AGENTCORE_RUNTIME_ENDPOINT = os.environ.get("AGENTCORE_RUNTIME_ENDPOINT", "")

# AgentCore RuntimeのランタイムID
AGENTCORE_RUNTIME_ID = os.environ.get("AGENTCORE_RUNTIME_ID", "")

# 対応するファイル拡張子
SUPPORTED_EXTENSIONS = {".txt", ".md"}

# -----------------------------------------------------------------------------
# Bedrock AgentCoreクライアントの初期化
# -----------------------------------------------------------------------------
# NOTE: Terraformで設定されるIAMロールにより、
#       bedrock-agentcore-runtime:InvokeAgent 権限が付与される
agentcore_client = boto3.client("bedrock-agentcore-runtime")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Lambda関数のエントリポイント。

    S3イベント通知を受け取り、AgentCore Runtimeに非同期処理をリクエストする。
    AgentCore Runtimeは即座にACKを返し、処理はバックグラウンドで実行される。

    Args:
        event: S3イベント通知
            {
                "Records": [
                    {
                        "s3": {
                            "bucket": {"name": "bucket-name"},
                            "object": {"key": "path/to/file.txt"}
                        }
                    }
                ]
            }
        context: Lambda実行コンテキスト

    Returns:
        処理受付結果
            {
                "statusCode": 200,
                "body": {
                    "accepted": [...],  # 処理を受け付けたファイル
                    "skipped": [...],   # スキップされたファイル
                    "errors": [...]     # エラーが発生したファイル
                }
            }
    """
    logger.info(f"イベント受信: {json.dumps(event, ensure_ascii=False)}")

    # 処理結果を格納するリスト
    accepted = []  # 処理を受け付けたファイル（非同期実行中）
    skipped = []   # スキップされたファイル
    errors = []    # エラーが発生したファイル

    # S3イベントのレコードを処理
    records = event.get("Records", [])

    if not records:
        logger.warning("処理対象のレコードがありません")
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "処理対象のレコードがありません",
                "accepted": [],
                "skipped": [],
                "errors": [],
            }, ensure_ascii=False),
        }

    for record in records:
        try:
            # S3イベント情報を抽出
            s3_info = record.get("s3", {})
            bucket = s3_info.get("bucket", {}).get("name", "")
            # URLエンコードされたキーをデコード
            key = urllib.parse.unquote_plus(
                s3_info.get("object", {}).get("key", "")
            )

            logger.info(f"処理対象: s3://{bucket}/{key}")

            # バケット名とキーの検証
            if not bucket or not key:
                error_msg = "バケット名またはキーが取得できません"
                logger.error(error_msg)
                errors.append({"bucket": bucket, "key": key, "error": error_msg})
                continue

            # ファイル拡張子のチェック
            file_extension = get_file_extension(key)
            if file_extension not in SUPPORTED_EXTENSIONS:
                skip_msg = (
                    f"サポートされていない拡張子のためスキップ: {file_extension}"
                )
                logger.info(skip_msg)
                skipped.append({"bucket": bucket, "key": key, "reason": skip_msg})
                continue

            # uploadsディレクトリ配下かチェック
            if "/uploads/" not in key:
                skip_msg = "uploadsディレクトリ配下ではないためスキップ"
                logger.info(skip_msg)
                skipped.append({"bucket": bucket, "key": key, "reason": skip_msg})
                continue

            # AgentCore Runtimeに非同期処理をリクエスト
            result = invoke_agentcore_runtime(bucket, key)

            if result.get("accepted"):
                accepted.append({
                    "bucket": bucket,
                    "key": key,
                    "task_id": result.get("task_id"),
                    "message": result.get("message"),
                })
            else:
                errors.append({
                    "bucket": bucket,
                    "key": key,
                    "error": result.get("message"),
                })

        except Exception as e:
            # 予期しないエラー
            logger.exception(f"レコード処理中にエラーが発生: {e}")
            errors.append({
                "bucket": bucket if "bucket" in dir() else "unknown",
                "key": key if "key" in dir() else "unknown",
                "error": str(e),
            })

    # 処理結果のサマリーをログ出力
    logger.info(
        f"処理完了: accepted={len(accepted)}, "
        f"skipped={len(skipped)}, errors={len(errors)}"
    )

    return {
        "statusCode": 200 if not errors else 207,  # 207 = Multi-Status
        "body": json.dumps({
            "accepted": accepted,
            "skipped": skipped,
            "errors": errors,
        }, ensure_ascii=False),
    }


def get_file_extension(key: str) -> str:
    """
    S3キーからファイル拡張子を取得する。

    Args:
        key: S3オブジェクトキー

    Returns:
        拡張子（ドット付き、小文字）。拡張子がない場合は空文字列。

    Example:
        >>> get_file_extension("path/to/file.txt")
        ".txt"
        >>> get_file_extension("path/to/file.MD")
        ".md"
        >>> get_file_extension("path/to/file")
        ""
    """
    if "." not in key:
        return ""
    return "." + key.split(".")[-1].lower()


def invoke_agentcore_runtime(bucket: str, key: str) -> dict[str, Any]:
    """
    AgentCore Runtimeに非同期処理をリクエストする。

    AgentCore Runtimeは即座にACKを返し、処理はバックグラウンドで実行される。
    処理結果はS3に直接保存される。

    Args:
        bucket: S3バケット名
        key: S3オブジェクトキー

    Returns:
        処理受付結果
            - accepted: 処理が受け付けられたかどうか
            - task_id: 非同期タスクのID（受付成功時）
            - message: 結果メッセージ
    """
    logger.info(f"AgentCore Runtime呼び出し: runtime_id={AGENTCORE_RUNTIME_ID}")

    # リクエストペイロードを作成
    payload = {
        "bucket": bucket,
        "key": key,
    }

    try:
        # AgentCore Runtimeを呼び出し
        # NOTE: boto3クライアントの正確なAPI仕様はAWSドキュメントを参照
        response = agentcore_client.invoke_agent(
            agentRuntimeId=AGENTCORE_RUNTIME_ID,
            # リクエストボディ
            inputText=json.dumps(payload),
        )

        # レスポンスを解析
        # NOTE: 実際のレスポンス形式はAgentCore Runtimeの実装に依存
        response_body = response.get("completion", "{}")
        if isinstance(response_body, str):
            result = json.loads(response_body)
        else:
            result = response_body

        logger.info(f"AgentCore Runtimeレスポンス: {result}")

        # 非同期実行の場合、status: "accepted" で成功
        if result.get("status") == "accepted":
            return {
                "accepted": True,
                "task_id": result.get("task_id"),
                "message": result.get("message", "処理を受け付けました"),
            }

        # エラーレスポンスの場合
        return {
            "accepted": False,
            "message": result.get("message", "処理の受付に失敗しました"),
        }

    except ClientError as e:
        # AWSサービスエラー
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = f"AgentCore Runtime呼び出しエラー（{error_code}）: {e}"
        logger.error(error_msg)
        return {
            "accepted": False,
            "message": error_msg,
        }

    except Exception as e:
        # その他のエラー
        error_msg = f"AgentCore Runtime呼び出し中に予期しないエラー: {e}"
        logger.exception(error_msg)
        return {
            "accepted": False,
            "message": error_msg,
        }
