# =============================================================================
# Lambda関数設定（非同期実行対応版）
# =============================================================================
# 概要:
#   S3イベントを受け取り、AgentCore Runtimeに非同期処理をリクエストする
#   プロキシLambda
#
# 処理フロー:
#   1. S3イベント通知を受信
#   2. AgentCore Runtimeに非同期処理をリクエスト
#   3. 即座にACKを受け取り、処理完了（短時間で終了）
#   4. 実際の処理はAgentCore Runtimeでバックグラウンド実行
#
# トリガー:
#   S3バケットへのオブジェクト作成イベント
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda関数
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "proxy" {
  function_name = "${local.name_prefix}-proxy"
  description   = "S3イベントをAgentCore Runtimeに転送するプロキシLambda"

  # ランタイム設定
  runtime       = "python3.12"
  architectures = ["arm64"]  # Graviton2（コスト効率が良い）
  handler       = "proxy_handler.handler"

  # コードの場所（デプロイ時にZIPを作成）
  filename         = data.archive_file.lambda_proxy.output_path
  source_code_hash = data.archive_file.lambda_proxy.output_base64sha256

  # 実行ロール
  role = aws_iam_role.lambda_proxy.arn

  # リソース設定
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  # 環境変数
  environment {
    variables = {
      # AgentCore RuntimeのID
      AGENTCORE_RUNTIME_ID = aws_bedrockagentcore_agent_runtime.summarizer.agent_runtime_id
      # ログレベル
      LOG_LEVEL = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  # VPC設定（オプション）
  dynamic "vpc_config" {
    for_each = var.vpc_id != "" ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  tags = {
    Name = "${local.name_prefix}-proxy"
    # 日本語コメント: S3イベントプロキシLambda
  }

  # ログ保持期間の設定が完了してから作成
  depends_on = [aws_cloudwatch_log_group.lambda_proxy]
}

# -----------------------------------------------------------------------------
# Lambda関数のZIPアーカイブ
# -----------------------------------------------------------------------------
data "archive_file" "lambda_proxy" {
  type        = "zip"
  source_file = "${path.module}/../lambda/proxy_handler.py"
  output_path = "${path.module}/../.build/lambda_proxy.zip"
}

# -----------------------------------------------------------------------------
# CloudWatch Logsグループ
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_proxy" {
  name = "/aws/lambda/${local.name_prefix}-proxy"

  # ログ保持期間（日数）
  retention_in_days = var.environment == "prod" ? 90 : 14

  tags = {
    Name = "${local.name_prefix}-proxy-logs"
    # 日本語コメント: プロキシLambdaのログ
  }
}

# -----------------------------------------------------------------------------
# S3からの呼び出し許可
# -----------------------------------------------------------------------------
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "s3.amazonaws.com"

  # 特定のS3バケットからのみ呼び出しを許可
  source_arn    = aws_s3_bucket.documents.arn
  source_account = local.account_id
}

# -----------------------------------------------------------------------------
# セキュリティグループ（VPC使用時のみ）
# -----------------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  count = var.vpc_id != "" ? 1 : 0

  name        = "${local.name_prefix}-lambda-sg"
  # NOTE: descriptionに日本語は使用不可
  description = "Security group for proxy Lambda function"
  vpc_id      = var.vpc_id

  # アウトバウンド: すべて許可（AgentCore Runtimeへのアクセス）
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # NOTE: descriptionに日本語は使用不可
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
    # 日本語コメント: プロキシLambda用SG
  }
}
