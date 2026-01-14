# =============================================================================
# IAM設定
# =============================================================================
# 概要:
#   Lambda関数およびAgentCore Runtime用のIAMロールとポリシーを定義
#   最小権限の原則に従い、必要な権限のみを付与
# =============================================================================

# =============================================================================
# プロキシLambda用IAM
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda実行ロール
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_proxy" {
  name = "${local.name_prefix}-lambda-proxy-role"

  # 信頼ポリシー: Lambdaサービスがこのロールを引き受けることを許可
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-lambda-proxy-role"
    # 日本語コメント: プロキシLambda用実行ロール
  }
}

# -----------------------------------------------------------------------------
# Lambda基本実行ポリシー（CloudWatch Logs）
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_proxy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------------------
# AgentCore Runtime呼び出しポリシー
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_agentcore" {
  name = "${local.name_prefix}-lambda-agentcore-policy"
  role = aws_iam_role.lambda_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # AgentCore Runtimeの呼び出し権限
        Sid    = "InvokeAgentCoreRuntime"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore-runtime:InvokeAgent"
        ]
        # 特定のランタイムのみに制限
        Resource = aws_bedrockagentcore_agent_runtime.summarizer.arn
      }
    ]
  })
}

# =============================================================================
# AgentCore Runtime用IAM
# =============================================================================

# -----------------------------------------------------------------------------
# AgentCore Runtime実行ロール
# -----------------------------------------------------------------------------
resource "aws_iam_role" "agentcore_runtime" {
  name = "${local.name_prefix}-agentcore-runtime-role"

  # 信頼ポリシー: AgentCoreサービスがこのロールを引き受けることを許可
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-agentcore-runtime-role"
    # 日本語コメント: AgentCore Runtime用実行ロール
  }
}

# -----------------------------------------------------------------------------
# S3アクセスポリシー
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "agentcore_s3" {
  name = "${local.name_prefix}-agentcore-s3-policy"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # S3オブジェクトの読み取り権限
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:HeadObject"
        ]
        # uploadsディレクトリのみに制限
        Resource = "${aws_s3_bucket.documents.arn}/*/uploads/*"
      },
      {
        # S3オブジェクトの書き込み権限
        Sid    = "S3Write"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        # summariesディレクトリのみに制限
        Resource = "${aws_s3_bucket.documents.arn}/*/summaries/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Bedrockモデル呼び出しポリシー
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "agentcore_bedrock" {
  name = "${local.name_prefix}-agentcore-bedrock-policy"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Bedrockモデルの呼び出し権限
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        # 特定のモデルのみに制限
        Resource = "arn:aws:bedrock:${local.region}::foundation-model/${var.bedrock_model_id}"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# AgentCoreMemoryアクセスポリシー
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "agentcore_memory" {
  name = "${local.name_prefix}-agentcore-memory-policy"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # AgentCoreMemoryの読み書き権限
        Sid    = "AgentCoreMemory"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetMemory",
          "bedrock-agentcore:CreateMemorySession",
          "bedrock-agentcore:UpdateMemorySession",
          "bedrock-agentcore:RetrieveMemory",
          "bedrock-agentcore:StoreMemory"
        ]
        # 特定のMemoryリソースのみに制限
        Resource = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:memory/${var.agentcore_memory_id}"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECRイメージ取得ポリシー
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "agentcore_ecr" {
  name = "${local.name_prefix}-agentcore-ecr-policy"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECRからのイメージ取得権限
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = aws_ecr_repository.agent.arn
      },
      {
        # ECR認証トークン取得権限
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Logsポリシー
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "agentcore_logs" {
  name = "${local.name_prefix}-agentcore-logs-policy"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch Logsへの書き込み権限
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/*"
      }
    ]
  })
}
