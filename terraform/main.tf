# =============================================================================
# Terraform メイン設定
# =============================================================================
# 概要:
#   プロバイダー設定、バックエンド設定、データソースを定義
#
# 使用方法:
#   1. terraform init
#   2. terraform plan
#   3. terraform apply
# =============================================================================

# -----------------------------------------------------------------------------
# Terraform設定
# -----------------------------------------------------------------------------
terraform {
  # Terraformバージョン制約
  required_version = ">= 1.5.0"

  # 必要なプロバイダー
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # バックエンド設定（必要に応じてコメントを外す）
  # S3バックエンドを使用する場合:
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "strands-doc-summarizer/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# -----------------------------------------------------------------------------
# AWSプロバイダー設定
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # デフォルトタグ（すべてのリソースに適用）
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# データソース
# -----------------------------------------------------------------------------

# 現在のAWSアカウントID
data "aws_caller_identity" "current" {}

# 現在のリージョン
data "aws_region" "current" {}

# 利用可能なAZs
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# ローカル変数
# -----------------------------------------------------------------------------
locals {
  # AWSアカウントID
  account_id = data.aws_caller_identity.current.account_id

  # リージョン名
  # NOTE: name は deprecated のため id を使用
  region = data.aws_region.current.id

  # リソース名のプレフィックス
  # 例: "strands-doc-summarizer-dev"
  name_prefix = "${var.project_name}-${var.environment}"

  # 共通タグ（default_tagsに追加するタグがある場合）
  common_tags = {
    Application = "document-summarizer"
  }
}
