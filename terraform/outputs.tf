# =============================================================================
# Terraform 出力値
# =============================================================================
# 概要:
#   terraform apply 後に表示される出力値を定義
#   他のモジュールやスクリプトから参照可能
# =============================================================================

# -----------------------------------------------------------------------------
# S3バケット
# -----------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "ドキュメント保存用S3バケット名"
  value       = aws_s3_bucket.documents.id
}

output "s3_bucket_arn" {
  description = "S3バケットのARN"
  value       = aws_s3_bucket.documents.arn
}

output "s3_upload_path" {
  description = "ファイルアップロード先のパス形式"
  value       = "s3://${aws_s3_bucket.documents.id}/{user_id}/uploads/"
}

output "s3_summary_path" {
  description = "要約の保存先パス形式"
  value       = "s3://${aws_s3_bucket.documents.id}/{user_id}/summaries/"
}

# -----------------------------------------------------------------------------
# ECRリポジトリ
# -----------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "ECRリポジトリURL"
  value       = aws_ecr_repository.agent.repository_url
}

output "ecr_repository_arn" {
  description = "ECRリポジトリARN"
  value       = aws_ecr_repository.agent.arn
}

output "docker_push_command" {
  description = "Dockerイメージをプッシュするコマンド"
  value       = <<-EOT
    # ECRにログイン
    aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.agent.repository_url}

    # イメージをビルド
    docker build --platform linux/arm64 -t ${aws_ecr_repository.agent.repository_url}:${var.ecr_image_tag} .

    # イメージをプッシュ
    docker push ${aws_ecr_repository.agent.repository_url}:${var.ecr_image_tag}
  EOT
}

# -----------------------------------------------------------------------------
# Lambda関数
# -----------------------------------------------------------------------------

output "lambda_function_name" {
  description = "プロキシLambda関数名"
  value       = aws_lambda_function.proxy.function_name
}

output "lambda_function_arn" {
  description = "プロキシLambda関数ARN"
  value       = aws_lambda_function.proxy.arn
}

output "lambda_log_group" {
  description = "LambdaのCloudWatch Logsグループ"
  value       = aws_cloudwatch_log_group.lambda_proxy.name
}

# -----------------------------------------------------------------------------
# AgentCore Runtime
# -----------------------------------------------------------------------------

output "agentcore_runtime_id" {
  description = "AgentCore RuntimeのID"
  value       = aws_bedrockagentcore_agent_runtime.summarizer.agent_runtime_id
}

output "agentcore_runtime_arn" {
  description = "AgentCore RuntimeのARN"
  value       = aws_bedrockagentcore_agent_runtime.summarizer.agent_runtime_arn
}

# -----------------------------------------------------------------------------
# AgentCore Memory
# -----------------------------------------------------------------------------

output "agentcore_memory_id" {
  description = "AgentCoreMemoryのID"
  value       = aws_bedrockagentcore_memory.main.id
}

output "agentcore_memory_arn" {
  description = "AgentCoreMemoryのARN"
  value       = aws_bedrockagentcore_memory.main.arn
}

output "agentcore_memory_strategy_id" {
  description = "AgentCoreMemory Strategyの名前"
  value       = aws_bedrockagentcore_memory_strategy.fact_extractor.name
}

# -----------------------------------------------------------------------------
# AgentCore Runtime ログ
# -----------------------------------------------------------------------------

output "agentcore_log_group_name" {
  description = "AgentCore Runtime ログの CloudWatch Log Group 名"
  value       = aws_cloudwatch_log_group.agentcore_runtime.name
}

output "agentcore_log_group_arn" {
  description = "AgentCore Runtime ログの CloudWatch Log Group ARN"
  value       = aws_cloudwatch_log_group.agentcore_runtime.arn
}

# -----------------------------------------------------------------------------
# IAMロール
# -----------------------------------------------------------------------------

output "lambda_role_arn" {
  description = "プロキシLambdaの実行ロールARN"
  value       = aws_iam_role.lambda_proxy.arn
}

output "agentcore_role_arn" {
  description = "AgentCore Runtimeの実行ロールARN"
  value       = aws_iam_role.agentcore_runtime.arn
}

# -----------------------------------------------------------------------------
# 使用方法ガイド
# -----------------------------------------------------------------------------

output "usage_guide" {
  description = "デプロイ後の使用方法"
  value       = <<-EOT
    ============================================================
    デプロイ完了！以下の手順でテストしてください:
    ============================================================

    1. テストファイルをアップロード:
       aws s3 cp test.txt s3://${aws_s3_bucket.documents.id}/alice/uploads/test.txt

    2. 処理状況をログで確認:
       aws logs tail ${aws_cloudwatch_log_group.lambda_proxy.name} --follow

    3. 要約を取得:
       aws s3 cp s3://${aws_s3_bucket.documents.id}/alice/summaries/test.txt.summary.txt -

    ============================================================
  EOT
}

# -----------------------------------------------------------------------------
# 環境変数設定ガイド
# -----------------------------------------------------------------------------

output "environment_variables" {
  description = "AgentCore Runtime用の環境変数"
  value = {
    AGENTCORE_MEMORY_ID = aws_bedrockagentcore_memory.main.id
    S3_BUCKET_NAME      = aws_s3_bucket.documents.id
    AWS_REGION          = local.region
    BEDROCK_MODEL_ID    = var.bedrock_model_id
  }
}
