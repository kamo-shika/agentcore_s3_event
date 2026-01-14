# =============================================================================
# Terraform 変数定義
# =============================================================================
# 概要:
#   プロジェクト全体で使用する変数を定義
#   デフォルト値を設定し、terraform.tfvars で上書き可能
# =============================================================================

# -----------------------------------------------------------------------------
# 基本設定
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "プロジェクト名（リソース名のプレフィックスに使用）"
  type        = string
  default     = "strands-doc-summarizer"
}

variable "environment" {
  description = "環境名（dev, staging, prod）"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "環境名は dev, staging, prod のいずれかである必要があります"
  }
}

# -----------------------------------------------------------------------------
# AgentCore設定
# -----------------------------------------------------------------------------

variable "agentcore_memory_id" {
  description = "AgentCoreMemoryのID（create_memory.pyで作成したもの）"
  type        = string
  # デフォルト値なし - 必ず指定が必要
}

variable "bedrock_model_id" {
  description = "使用するBedrockモデルID（Claude Haiku 4.5）"
  type        = string
  default     = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
}

# -----------------------------------------------------------------------------
# Lambda設定
# -----------------------------------------------------------------------------

variable "lambda_timeout" {
  description = "プロキシLambdaのタイムアウト（秒）"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "タイムアウトは1〜900秒の範囲で指定してください"
  }
}

variable "lambda_memory_size" {
  description = "プロキシLambdaのメモリサイズ（MB）"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "メモリサイズは128〜10240MBの範囲で指定してください"
  }
}

# -----------------------------------------------------------------------------
# AgentCore Runtime設定
# -----------------------------------------------------------------------------

variable "agentcore_runtime_timeout" {
  description = "AgentCore Runtimeのタイムアウト（秒）"
  type        = number
  default     = 120
}

variable "agentcore_runtime_memory" {
  description = "AgentCore Runtimeのメモリサイズ（MB）"
  type        = number
  default     = 512
}

# -----------------------------------------------------------------------------
# S3設定
# -----------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "S3バケット名（空の場合は自動生成）"
  type        = string
  default     = ""
}

variable "s3_versioning_enabled" {
  description = "S3バージョニングを有効にするか"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ECR設定
# -----------------------------------------------------------------------------

variable "ecr_repository_name" {
  description = "ECRリポジトリ名（空の場合は自動生成）"
  type        = string
  default     = ""
}

variable "ecr_image_tag" {
  description = "使用するDockerイメージタグ"
  type        = string
  default     = "latest"
}

# -----------------------------------------------------------------------------
# ネットワーク設定（オプション）
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID（プライベートネットワークを使用する場合）"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "サブネットID一覧（プライベートネットワークを使用する場合）"
  type        = list(string)
  default     = []
}
