# =============================================================================
# ドキュメント操作ツール
# =============================================================================
# 概要:
#   Strands Agent用のカスタムツール
#   S3上のテキストファイルの読み取りと要約の保存を行う
#
# 利用可能なツール:
#   - read_text_file: S3からテキストファイルを読み取る
#   - save_summary: 要約をS3に保存する
# =============================================================================

from __future__ import annotations

import logging
import os
from typing import Literal

import boto3
from botocore.exceptions import ClientError
from strands import tool

# -----------------------------------------------------------------------------
# ロガーの設定
# -----------------------------------------------------------------------------
logger = logging.getLogger(__name__)

# -----------------------------------------------------------------------------
# 定数定義
# -----------------------------------------------------------------------------
# AWSリージョン
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# 対応するファイル拡張子
SUPPORTED_EXTENSIONS = {".txt", ".md"}

# ファイルサイズ上限（10MB）
# これ以上大きいファイルはLLMのコンテキスト制限に引っかかる可能性がある
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024

# -----------------------------------------------------------------------------
# S3クライアントの初期化
# -----------------------------------------------------------------------------
# NOTE: Lambda/AgentCore Runtime環境では、IAMロールから自動的に認証情報を取得
s3_client = boto3.client("s3", region_name=AWS_REGION)


@tool
def read_text_file(bucket: str, key: str) -> str:
    """
    S3からテキストファイルを読み取る。

    指定されたS3バケットとキーからテキストファイルを取得し、
    UTF-8としてデコードして内容を返す。

    対応するファイル形式:
    - .txt: プレーンテキスト
    - .md: Markdown

    Args:
        bucket: S3バケット名
            例: "my-document-bucket"
        key: S3オブジェクトキー
            例: "alice/uploads/report.txt"

    Returns:
        ファイルの内容（UTF-8テキスト）

    Raises:
        FileNotFoundError: ファイルが存在しない場合
        ValueError: サポートされていないファイル形式の場合
        ValueError: ファイルサイズが上限を超えている場合
        UnicodeDecodeError: UTF-8としてデコードできない場合

    Example:
        >>> content = read_text_file("my-bucket", "alice/uploads/report.txt")
        >>> print(content[:100])
        "# 月次報告書\\n\\n## 概要\\n..."
    """
    logger.info(f"ファイル読み取り開始: s3://{bucket}/{key}")

    # ファイル拡張子のチェック
    file_extension = "." + key.split(".")[-1].lower() if "." in key else ""
    if file_extension not in SUPPORTED_EXTENSIONS:
        error_msg = (
            f"サポートされていないファイル形式です: {file_extension} "
            f"（対応形式: {', '.join(SUPPORTED_EXTENSIONS)}）"
        )
        logger.error(error_msg)
        raise ValueError(error_msg)

    try:
        # オブジェクトのメタデータを取得してサイズをチェック
        head_response = s3_client.head_object(Bucket=bucket, Key=key)
        file_size = head_response["ContentLength"]

        logger.info(f"ファイルサイズ: {file_size} bytes")

        # ファイルサイズ上限チェック
        if file_size > MAX_FILE_SIZE_BYTES:
            error_msg = (
                f"ファイルサイズが上限を超えています: {file_size} bytes "
                f"（上限: {MAX_FILE_SIZE_BYTES} bytes）"
            )
            logger.error(error_msg)
            raise ValueError(error_msg)

        # ファイル内容を取得
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content_bytes = response["Body"].read()

        # UTF-8としてデコード
        try:
            content = content_bytes.decode("utf-8")
        except UnicodeDecodeError as e:
            # UTF-8以外のエンコーディングの場合
            error_msg = f"ファイルをUTF-8としてデコードできません: {e}"
            logger.error(error_msg)
            raise UnicodeDecodeError(
                "utf-8",
                content_bytes,
                0,
                len(content_bytes),
                "UTF-8以外のエンコーディングです。UTF-8形式で保存してください。",
            )

        logger.info(f"ファイル読み取り完了: 文字数={len(content)}")
        return content

    except s3_client.exceptions.NoSuchKey:
        # ファイルが存在しない場合
        error_msg = f"ファイルが見つかりません: s3://{bucket}/{key}"
        logger.error(error_msg)
        raise FileNotFoundError(error_msg)

    except ClientError as e:
        # その他のS3エラー
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = f"S3エラーが発生しました（{error_code}）: {e}"
        logger.error(error_msg)
        raise


@tool
def save_summary(bucket: str, key: str, summary: str) -> dict[str, str]:
    """
    要約をS3に保存する。

    生成された要約をS3の指定された場所に保存する。
    ファイルはUTF-8エンコーディングで保存される。

    Args:
        bucket: S3バケット名
            例: "my-document-bucket"
        key: 保存先のS3オブジェクトキー
            例: "alice/summaries/report.summary.txt"
        summary: 保存する要約テキスト

    Returns:
        保存結果を含む辞書:
            - status: "success" または "error"
            - location: 保存されたファイルのS3 URI
            - message: 結果メッセージ

    Raises:
        ClientError: S3への保存に失敗した場合

    Example:
        >>> result = save_summary(
        ...     "my-bucket",
        ...     "alice/summaries/report.summary.txt",
        ...     "# 要約\\n\\n重要なポイント..."
        ... )
        >>> print(result)
        {
            "status": "success",
            "location": "s3://my-bucket/alice/summaries/report.summary.txt",
            "message": "要約を保存しました"
        }
    """
    logger.info(f"要約保存開始: s3://{bucket}/{key}")
    logger.info(f"要約の長さ: {len(summary)} 文字")

    try:
        # UTF-8でエンコードしてS3に保存
        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=summary.encode("utf-8"),
            ContentType="text/plain; charset=utf-8",
            # メタデータとして生成情報を付与
            Metadata={
                "generated-by": "strands-doc-summarizer",
                "content-type": "summary",
            },
        )

        location = f"s3://{bucket}/{key}"
        logger.info(f"要約保存完了: {location}")

        return {
            "status": "success",
            "location": location,
            "message": "要約を保存しました",
        }

    except ClientError as e:
        # S3への保存に失敗した場合
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = f"要約の保存に失敗しました（{error_code}）: {e}"
        logger.error(error_msg)

        return {
            "status": "error",
            "location": None,
            "message": error_msg,
        }
