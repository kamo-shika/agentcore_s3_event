# =============================================================================
# AgentCore Runtime設定
# =============================================================================
# 概要:
#   Strands Agentをホストする AgentCore Runtime を定義
#   コンテナイメージはECRから取得
#
# NOTE:
#   このリソースは terraform-provider-aws の将来のバージョンで
#   サポートされる予定です。現時点では aws_bedrockagentcore_agent_runtime
#   リソースが利用できない場合があります。
#
#   その場合は、AWS CLIまたはboto3で手動作成してください:
#   aws bedrock-agentcore-control create-agent-runtime ...
# =============================================================================

# -----------------------------------------------------------------------------
# AgentCore Runtime
# -----------------------------------------------------------------------------
# NOTE: terraform-provider-awsでAgentCore Runtimeがサポートされていない場合、
#       このリソースはコメントアウトし、null_resourceで代替するか、
#       手動でAWS CLIを使用して作成してください。
# -----------------------------------------------------------------------------

# AgentCore Runtime リソース（プロバイダーサポート時）
resource "aws_bedrockagentcore_agent_runtime" "summarizer" {
  # ランタイム名
  agent_runtime_name = "${local.name_prefix}-runtime"

  # コンテナ設定
  agent_runtime_artifact {
    container_configuration {
      # ECRからコンテナイメージを取得
      container_uri = "${aws_ecr_repository.agent.repository_url}:${var.ecr_image_tag}"
    }
  }

  # ネットワーク設定
  # PUBLIC: インターネット経由でアクセス可能
  network_configuration {
    network_mode = "PUBLIC"
  }

  # プロトコル設定
  protocol_configuration {
    server_protocol = "HTTP"
  }

  # IAMロール
  role_arn = aws_iam_role.agentcore_runtime.arn

  # 環境変数
  # NOTE: AgentCore Runtimeの環境変数設定方法は
  #       AWSドキュメントを参照してください
  # environment_variables = {
  #   AGENTCORE_MEMORY_ID = var.agentcore_memory_id
  #   S3_BUCKET_NAME      = aws_s3_bucket.documents.id
  #   AWS_REGION          = local.region
  #   BEDROCK_MODEL_ID    = var.bedrock_model_id
  # }

  tags = {
    Name = "${local.name_prefix}-runtime"
    # 日本語コメント: ドキュメント要約エージェントランタイム
  }
}

# -----------------------------------------------------------------------------
# 代替: AWS CLIを使用した手動作成（プロバイダー非サポート時）
# -----------------------------------------------------------------------------
# terraform-provider-awsでAgentCore Runtimeがサポートされていない場合、
# 以下のnull_resourceを使用してAWS CLIで作成することができます。
# ただし、terraform destroyでの削除は手動で行う必要があります。
# -----------------------------------------------------------------------------

# resource "null_resource" "agentcore_runtime" {
#   # トリガー: ECRイメージタグが変更されたら再作成
#   triggers = {
#     image_tag = var.ecr_image_tag
#   }
#
#   provisioner "local-exec" {
#     command = <<-EOT
#       aws bedrock-agentcore-control create-agent-runtime \
#         --agent-runtime-name "${local.name_prefix}-runtime" \
#         --agent-runtime-artifact containerConfiguration={containerUri=${aws_ecr_repository.agent.repository_url}:${var.ecr_image_tag}} \
#         --role-arn "${aws_iam_role.agentcore_runtime.arn}" \
#         --network-configuration networkMode=PUBLIC \
#         --protocol-configuration serverProtocol=HTTP \
#         --region ${local.region}
#     EOT
#   }
#
#   depends_on = [
#     aws_iam_role.agentcore_runtime,
#     aws_ecr_repository.agent
#   ]
# }

# -----------------------------------------------------------------------------
# AgentCore Runtime のステータス確認用データソース
# -----------------------------------------------------------------------------
# NOTE: ランタイムが作成された後、ACTIVE状態になるまで待機が必要な場合があります
# data "aws_bedrockagentcore_agent_runtime" "summarizer" {
#   agent_runtime_id = aws_bedrockagentcore_agent_runtime.summarizer.id
# }
