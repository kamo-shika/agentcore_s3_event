#!/usr/bin/env python3
# =============================================================================
# AgentCoreMemory 初期セットアップスクリプト
# =============================================================================
# 概要:
#   AgentCoreMemoryのリソースを作成する
#   このスクリプトは初回デプロイ時に一度だけ実行する
#
# 実行方法:
#   python setup/create_memory.py
#
# 必要な権限:
#   - bedrock-agentcore:CreateMemory
#   - bedrock-agentcore:GetMemory
#
# 出力:
#   - Memory ID（環境変数 AGENTCORE_MEMORY_ID として使用）
# =============================================================================

from __future__ import annotations

import argparse
import json
import os
import sys
import time

import boto3
from botocore.exceptions import ClientError

# -----------------------------------------------------------------------------
# 定数定義
# -----------------------------------------------------------------------------
# デフォルトのAWSリージョン
DEFAULT_REGION = "us-east-1"

# Memory名のプレフィックス
MEMORY_NAME_PREFIX = "strands-doc-summarizer"

# ポーリング間隔（秒）
POLLING_INTERVAL_SECONDS = 5

# タイムアウト（秒）
CREATION_TIMEOUT_SECONDS = 300


def create_memory(
    region: str = DEFAULT_REGION,
    memory_name: str | None = None,
) -> dict[str, str]:
    """
    AgentCoreMemoryを作成する。

    semanticMemoryStrategyを使用して、事実抽出による長期記憶を設定する。

    Args:
        region: AWSリージョン
        memory_name: Memoryの名前（指定しない場合は自動生成）

    Returns:
        作成結果を含む辞書:
            - memory_id: 作成されたMemoryのID
            - memory_name: Memoryの名前
            - status: 作成ステータス

    Raises:
        RuntimeError: Memory作成に失敗した場合
    """
    print(f"AgentCoreMemory作成を開始します...")
    print(f"リージョン: {region}")

    # Memory名を生成
    if memory_name is None:
        # タイムスタンプを付与してユニークな名前を生成
        timestamp = int(time.time())
        memory_name = f"{MEMORY_NAME_PREFIX}-{timestamp}"

    print(f"Memory名: {memory_name}")

    # クライアントを初期化
    # NOTE: bedrock_agentcore.memory.MemoryClient を使用する方法もある
    try:
        from bedrock_agentcore.memory import MemoryClient
        client = MemoryClient(region_name=region)
        use_memory_client = True
    except ImportError:
        # bedrock-agentcore-memory がインストールされていない場合は boto3 を使用
        print("警告: bedrock-agentcore-memory がインストールされていません")
        print("boto3 を使用して作成を試みます...")
        client = boto3.client("bedrock-agentcore", region_name=region)
        use_memory_client = False

    # Memoryの設定
    # semanticMemoryStrategy: 事実を抽出してベクトル化し、検索可能にする
    memory_config = {
        "name": memory_name,
        "description": "ドキュメント要約エージェント用の長期記憶。事実抽出により過去の情報を保持。",
        "strategies": [
            {
                # 事実抽出戦略
                # ドキュメントから重要な事実を抽出し、セマンティック検索可能にする
                "semanticMemoryStrategy": {
                    "name": "FactExtractor",
                    # ネームスペース: /facts/{actorId} 形式
                    # actorId = ユーザーID（S3キーから抽出）
                    "namespaces": ["/facts/{actorId}"],
                }
            },
        ],
    }

    print("Memory設定:")
    print(json.dumps(memory_config, indent=2, ensure_ascii=False))

    try:
        if use_memory_client:
            # bedrock-agentcore-memory の MemoryClient を使用
            # create_memory_and_wait は作成完了まで待機する
            print("\nMemory作成中（完了まで待機）...")
            result = client.create_memory_and_wait(**memory_config)
            memory_id = result.get("id")
            status = "ACTIVE"
        else:
            # boto3 を使用
            response = client.create_memory(**memory_config)
            memory_id = response.get("memoryId")

            # 作成完了を待機
            print("\nMemory作成中...")
            status = wait_for_memory_creation(client, memory_id)

        print(f"\nMemory作成完了!")
        print(f"Memory ID: {memory_id}")
        print(f"ステータス: {status}")

        # 環境変数設定のガイダンスを出力
        print("\n" + "=" * 60)
        print("次のステップ:")
        print("=" * 60)
        print("\n1. 環境変数を設定してください:")
        print(f"   export AGENTCORE_MEMORY_ID={memory_id}")
        print("\n2. Terraformの変数ファイルに追記してください:")
        print(f'   agentcore_memory_id = "{memory_id}"')
        print("=" * 60)

        return {
            "memory_id": memory_id,
            "memory_name": memory_name,
            "status": status,
        }

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = f"Memory作成エラー（{error_code}）: {e}"
        print(f"エラー: {error_msg}", file=sys.stderr)
        raise RuntimeError(error_msg) from e

    except Exception as e:
        error_msg = f"予期しないエラー: {e}"
        print(f"エラー: {error_msg}", file=sys.stderr)
        raise RuntimeError(error_msg) from e


def wait_for_memory_creation(
    client: boto3.client,
    memory_id: str,
    timeout_seconds: int = CREATION_TIMEOUT_SECONDS,
) -> str:
    """
    Memory作成の完了を待機する。

    Args:
        client: boto3クライアント
        memory_id: 待機対象のMemory ID
        timeout_seconds: タイムアウト秒数

    Returns:
        最終的なステータス

    Raises:
        RuntimeError: タイムアウトまたは作成失敗の場合
    """
    start_time = time.time()
    last_status = ""

    while True:
        # タイムアウトチェック
        elapsed = time.time() - start_time
        if elapsed > timeout_seconds:
            raise RuntimeError(
                f"Memory作成がタイムアウトしました（{timeout_seconds}秒）"
            )

        try:
            # ステータスを取得
            response = client.get_memory(memoryId=memory_id)
            status = response.get("status", "UNKNOWN")

            # ステータスが変わったらログ出力
            if status != last_status:
                print(f"  ステータス: {status}")
                last_status = status

            # 完了チェック
            if status == "ACTIVE":
                return status
            elif status in ("FAILED", "DELETED"):
                raise RuntimeError(f"Memory作成が失敗しました: {status}")

            # ポーリング間隔を待機
            time.sleep(POLLING_INTERVAL_SECONDS)

        except ClientError as e:
            # 一時的なエラーの場合はリトライ
            print(f"  警告: ステータス取得エラー: {e}")
            time.sleep(POLLING_INTERVAL_SECONDS)


def main():
    """
    メイン関数。

    コマンドライン引数を解析し、Memory作成を実行する。
    """
    parser = argparse.ArgumentParser(
        description="AgentCoreMemoryを作成する",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  python setup/create_memory.py
  python setup/create_memory.py --region us-west-2
  python setup/create_memory.py --name my-custom-memory
        """,
    )

    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", DEFAULT_REGION),
        help=f"AWSリージョン（デフォルト: {DEFAULT_REGION}）",
    )

    parser.add_argument(
        "--name",
        default=None,
        help="Memory名（指定しない場合は自動生成）",
    )

    args = parser.parse_args()

    try:
        result = create_memory(
            region=args.region,
            memory_name=args.name,
        )
        # 成功時は正常終了
        sys.exit(0)

    except RuntimeError as e:
        print(f"\n作成に失敗しました: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
