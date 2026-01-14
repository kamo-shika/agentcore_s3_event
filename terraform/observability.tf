# =============================================================================
# オブザーバビリティ設定
# =============================================================================
# 概要:
#   AgentCore Runtime のログ管理設定を定義
#   ログ保持期間の設定により、コスト最適化を実現
#
# 参考:
#   AgentCore Runtime は自動的に以下のパスにログを出力する:
#   - /aws/bedrock-agentcore/runtimes/<agent_id>-<endpoint_name>/[runtime-logs] <UUID>
#   - /aws/bedrock-agentcore/runtimes/<agent_id>-<endpoint_name>/otel-rt-logs
#
#   事前に Log Group を作成しておくことで、保持期間等を制御可能
# =============================================================================

# -----------------------------------------------------------------------------
# AgentCore Runtime ログ用 CloudWatch Log Group
# -----------------------------------------------------------------------------
# NOTE: AgentCore Runtime は自動的にこのパス配下にログを出力する
#       Log Group を事前作成することで、保持期間を Terraform で管理できる
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "agentcore_runtime" {
  name              = "/aws/bedrock-agentcore/runtimes"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-agentcore-runtime-logs"
    # 日本語コメント: AgentCore Runtime ログ用ロググループ
  }
}
