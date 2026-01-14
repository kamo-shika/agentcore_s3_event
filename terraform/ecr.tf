# =============================================================================
# ECR（Elastic Container Registry）設定
# =============================================================================
# 概要:
#   AgentCore Runtime用のDockerイメージを保存するECRリポジトリを定義
#
# 使用方法:
#   1. scripts/build_and_push.sh でイメージをビルド＆プッシュ
#   2. AgentCore Runtimeがこのリポジトリからイメージを取得
# =============================================================================

# -----------------------------------------------------------------------------
# ECRリポジトリ
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "agent" {
  # リポジトリ名
  name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${local.name_prefix}-agent"

  # イメージタグの上書きを許可（開発時は便利）
  image_tag_mutability = "MUTABLE"

  # イメージスキャン設定
  image_scanning_configuration {
    # プッシュ時に自動スキャン
    scan_on_push = true
  }

  # 暗号化設定
  encryption_configuration {
    # AES256暗号化（デフォルト）
    encryption_type = "AES256"
  }

  tags = {
    Name = "${local.name_prefix}-agent"
    # 日本語コメント: AgentCore Runtime用コンテナリポジトリ
  }
}

# -----------------------------------------------------------------------------
# ライフサイクルポリシー
# -----------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  # ライフサイクルルール
  policy = jsonencode({
    rules = [
      {
        # ルール1: 未タグ付きイメージを7日後に削除
        rulePriority = 1
        description  = "未タグ付きイメージを7日後に削除"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        # ルール2: 古いイメージを保持数制限で削除（最新10個を保持）
        rulePriority = 2
        description  = "古いイメージを削除（最新10個を保持）"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# リポジトリポリシー（クロスアカウントアクセスが必要な場合）
# -----------------------------------------------------------------------------
# NOTE: 同一アカウント内での使用なら不要
# resource "aws_ecr_repository_policy" "agent" {
#   repository = aws_ecr_repository.agent.name
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "AllowPull"
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:aws:iam::${local.account_id}:root"
#         }
#         Action = [
#           "ecr:GetDownloadUrlForLayer",
#           "ecr:BatchGetImage"
#         ]
#       }
#     ]
#   })
# }
