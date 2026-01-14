# =============================================================================
# AgentCore Memory設定
# =============================================================================
# 概要:
#   AgentCoreMemoryとMemory Strategyを定義
#   Strands Agentの長期記憶として使用
#
# リソース:
#   - aws_bedrockagentcore_memory: メモリ本体
#   - aws_bedrockagentcore_memory_strategy: セマンティック検索戦略
# =============================================================================

# -----------------------------------------------------------------------------
# AgentCore Memory
# -----------------------------------------------------------------------------
# ドキュメント要約エージェント用の長期記憶
# semanticMemoryStrategyで事実を抽出し、検索可能にする
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory" "main" {
  # メモリ名
  name = "${local.name_prefix}-memory"

  # メモリの説明
  description = "ドキュメント要約エージェント用の長期記憶。事実抽出により過去の情報を保持。"

  # イベント有効期限（日数）
  # この期間を過ぎたメモリイベントは自動的に削除される
  event_expiry_duration = var.memory_event_expiry_days

  # メモリ実行ロール
  # Bedrockモデルを呼び出すための権限が必要
  memory_execution_role_arn = aws_iam_role.agentcore_memory.arn

  tags = {
    Name = "${local.name_prefix}-memory"
    # 日本語コメント: ドキュメント要約用長期記憶
  }
}

# -----------------------------------------------------------------------------
# Semantic Memory Strategy
# -----------------------------------------------------------------------------
# 事実抽出戦略
# ドキュメントから重要な事実を抽出し、セマンティック検索可能にする
#
# namespaces: /facts/{actorId} 形式
#   actorId = ユーザーID（S3キーの最初のセグメントから抽出）
#   例: /facts/alice, /facts/bob
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory_strategy" "fact_extractor" {
  # 戦略名
  name = "FactExtractor"

  # 関連付けるメモリID
  memory_id = aws_bedrockagentcore_memory.main.id

  # 戦略タイプ
  # SEMANTIC: セマンティック検索による事実抽出
  type = "SEMANTIC"

  # 名前空間
  # {actorId} はユーザーIDに置換される
  namespaces = ["/facts/{actorId}"]

  # 戦略の説明
  description = "事実抽出による長期記憶戦略。ドキュメントから重要な事実を抽出しセマンティック検索可能にする。"
}
