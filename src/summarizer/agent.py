# =============================================================================
# Strands Agent - ドキュメント要約エージェント
# =============================================================================
# 概要:
#   S3からテキストファイルを読み取り、過去の関連事実を参照しながら
#   文脈を踏まえた要約を生成するエージェント
#
# 処理フロー:
#   1. AgentCoreMemoryから関連事実をセマンティック検索
#   2. S3からテキストファイルを読み取り
#   3. 過去の事実を参照しながらClaude Haiku 4.5で要約生成
#   4. 新たな事実をAgentCoreMemoryに保存
#   5. 要約をS3に保存
# =============================================================================

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any

from bedrock_agentcore.memory import MemoryClient
from bedrock_agentcore.memory.integrations.strands.config import (
    AgentCoreMemoryConfig,
    RetrievalConfig,
)
from bedrock_agentcore.memory.integrations.strands.session_manager import (
    AgentCoreMemorySessionManager,
)
from strands import Agent
from strands.models import BedrockModel

from .tools import read_text_file, save_summary

# -----------------------------------------------------------------------------
# ロガーの設定
# -----------------------------------------------------------------------------
logger = logging.getLogger(__name__)

# -----------------------------------------------------------------------------
# 定数定義
# -----------------------------------------------------------------------------
# AWSリージョン
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# Bedrockモデル設定
# Claude Haiku 4.5（高速・低コスト）
MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID",
    "us.anthropic.claude-3-5-haiku-20241022-v1:0"
)

# セマンティック検索の設定
# 関連事実を最大10件取得、関連度スコア0.5以上
RETRIEVAL_TOP_K = 10
RETRIEVAL_RELEVANCE_SCORE = 0.5

# -----------------------------------------------------------------------------
# システムプロンプト
# -----------------------------------------------------------------------------
SUMMARIZER_SYSTEM_PROMPT = """
あなたは文書要約アシスタントです。

## 役割
- アップロードされたテキストファイルを読み取り、要約を生成します
- 過去に処理したドキュメントからの関連情報がある場合は、それを参照して文脈を踏まえた要約を作成します

## 要約のルール
1. 要約は日本語で作成してください
2. 要約は300文字以内を目安にしてください
3. 重要なポイントを箇条書きで整理してください
4. 事実に基づいた内容のみを記載してください
5. 推測や解釈は含めないでください

## 過去の関連情報がある場合
- 前回からの変化や進捗があれば言及してください
- 関連する過去の事実を参照しながら、文脈を踏まえた要約を作成してください
- 例: 「前回の報告では○○でしたが、今回は△△に変化しています」

## 出力形式
以下の形式で要約を出力してください:

### 要約
（要約本文）

### 主要ポイント
- ポイント1
- ポイント2
- ポイント3

### 抽出された事実
（長期記憶に保存すべき重要な事実を箇条書きで列挙）
"""


def create_session_manager(
    memory_id: str,
    actor_id: str,
    session_id: str,
) -> AgentCoreMemorySessionManager:
    """
    AgentCoreMemory用のセッションマネージャーを作成する。

    セマンティック検索の設定を含む長期記憶用のセッションマネージャーを構成。
    /facts/{actorId} ネームスペースから関連事実を検索する。

    Args:
        memory_id: AgentCoreMemoryのID
        actor_id: ユーザーID（S3キーから抽出）
        session_id: セッションID（ファイル名_タイムスタンプ）

    Returns:
        設定済みのセッションマネージャー
    """
    logger.info(f"セッションマネージャー作成: memory_id={memory_id}, actor_id={actor_id}")

    # AgentCoreMemoryの設定
    # /facts/{actorId} ネームスペースからセマンティック検索
    config = AgentCoreMemoryConfig(
        memory_id=memory_id,
        session_id=session_id,
        actor_id=actor_id,
        # 関連事実の検索設定
        retrieval_config={
            f"/facts/{actor_id}": RetrievalConfig(
                top_k=RETRIEVAL_TOP_K,
                relevance_score=RETRIEVAL_RELEVANCE_SCORE,
            )
        },
    )

    # セッションマネージャーを作成
    session_manager = AgentCoreMemorySessionManager(
        agentcore_memory_config=config,
        region_name=AWS_REGION,
    )

    return session_manager


def create_agent(session_manager: AgentCoreMemorySessionManager) -> Agent:
    """
    Strands Agentを作成する。

    Claude Haiku 4.5を使用し、カスタムツールとセッションマネージャーを設定。

    Args:
        session_manager: AgentCoreMemory用セッションマネージャー

    Returns:
        設定済みのStrands Agent
    """
    logger.info(f"Strands Agent作成: model_id={MODEL_ID}")

    # Bedrockモデルの設定
    model = BedrockModel(
        model_id=MODEL_ID,
        # 追加のリクエストパラメータ
        additional_request_fields={
            # thinkingモードを無効化（高速化のため）
            "thinking": {"type": "disabled"},
        },
    )

    # エージェントを作成
    agent = Agent(
        model=model,
        system_prompt=SUMMARIZER_SYSTEM_PROMPT,
        # カスタムツールを設定
        tools=[read_text_file, save_summary],
        # セッションマネージャー（長期記憶）
        session_manager=session_manager,
    )

    return agent


def process_document(
    bucket: str,
    key: str,
    actor_id: str,
    memory_id: str,
) -> dict[str, Any]:
    """
    ドキュメントを処理して要約を生成する。

    メインの処理関数。以下のステップを実行:
    1. セッションマネージャーを作成（過去の事実を検索可能に）
    2. Strands Agentを作成
    3. エージェントにドキュメント処理を依頼
    4. 結果を返却

    Args:
        bucket: S3バケット名
        key: S3オブジェクトキー（例: "alice/uploads/report.txt"）
        actor_id: ユーザーID
        memory_id: AgentCoreMemoryのID

    Returns:
        処理結果を含む辞書
            - success: 処理成功フラグ
            - summary_key: 保存された要約のS3キー
            - message: 結果メッセージ
    """
    logger.info(f"ドキュメント処理開始: bucket={bucket}, key={key}")

    # ファイル名を取得
    filename = key.split("/")[-1]
    # ファイル名から拡張子を除去した名前
    filename_without_ext = filename.rsplit(".", 1)[0]

    # セッションIDを生成（ファイル名_タイムスタンプ）
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    session_id = f"{filename_without_ext}_{timestamp}"

    logger.info(f"セッションID生成: {session_id}")

    # 要約の保存先キーを生成
    # {user_id}/uploads/{filename} → {user_id}/summaries/{filename}.summary.txt
    path_parts = key.split("/")
    summary_key = f"{path_parts[0]}/summaries/{filename}.summary.txt"

    try:
        # セッションマネージャーを作成
        # 過去の関連事実がセマンティック検索で取得される
        session_manager = create_session_manager(
            memory_id=memory_id,
            actor_id=actor_id,
            session_id=session_id,
        )

        # Strands Agentを作成
        agent = create_agent(session_manager)

        # エージェントへの指示
        # 過去の関連事実は自動的にコンテキストに含まれる
        prompt = f"""
以下のドキュメントを読み取り、要約を生成してください。

## 対象ドキュメント
- S3バケット: {bucket}
- S3キー: {key}

## 処理手順
1. read_text_file ツールを使ってドキュメントを読み取ってください
2. 内容を分析し、要約を生成してください
3. save_summary ツールを使って要約を保存してください
   - バケット: {bucket}
   - キー: {summary_key}

過去の関連情報がある場合は、それを参照して文脈を踏まえた要約を作成してください。
"""

        logger.info("エージェント実行開始")

        # エージェントを実行
        response = agent(prompt)

        logger.info(f"エージェント実行完了: {response}")

        # 成功レスポンスを返却
        return {
            "success": True,
            "summary_key": summary_key,
            "message": "要約を正常に生成しました",
            "session_id": session_id,
        }

    except Exception as e:
        # エラーハンドリング
        logger.exception(f"ドキュメント処理エラー: {e}")
        return {
            "success": False,
            "summary_key": None,
            "message": f"処理中にエラーが発生しました: {e}",
        }
