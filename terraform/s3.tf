# =============================================================================
# S3バケット設定
# =============================================================================
# 概要:
#   ドキュメントのアップロード先および要約の保存先となるS3バケットを定義
#   S3イベント通知でLambdaをトリガー
#
# バケット構造:
#   {user_id}/uploads/   - 入力ファイル（.txt, .md）
#   {user_id}/summaries/ - 生成された要約
# =============================================================================

# -----------------------------------------------------------------------------
# S3バケット
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "documents" {
  # バケット名（指定がなければ自動生成）
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-documents-${local.account_id}"

  # 削除時の保護（本番環境では true に設定推奨）
  force_destroy = var.environment != "prod"

  tags = {
    Name = "${local.name_prefix}-documents"
    # 日本語コメント: ドキュメントアップロード・要約保存用バケット
  }
}

# -----------------------------------------------------------------------------
# バケットのバージョニング設定
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    # バージョニングの有効/無効
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# バケットの暗号化設定
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3（AmazonS3管理キー）を使用
      sse_algorithm = "AES256"
    }
    # バケットキーを有効化（コスト削減）
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# パブリックアクセスブロック
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  # すべてのパブリックアクセスをブロック
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# S3イベント通知設定
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "documents" {
  bucket = aws_s3_bucket.documents.id

  # Lambda関数への通知設定
  lambda_function {
    # 通知先のLambda関数
    lambda_function_arn = aws_lambda_function.proxy.arn

    # トリガーするイベント（オブジェクト作成時）
    events = ["s3:ObjectCreated:*"]

    # フィルター: uploadsディレクトリ配下のみ
    # NOTE: ユーザーIDはワイルドカードで対応
    filter_prefix = ""  # すべてのプレフィックスを対象（uploadsチェックはLambda内で実施）

    # フィルター: .txt と .md ファイルのみ
    # NOTE: S3通知では複数の拡張子フィルターを設定できないため、
    #       Lambdaハンドラー内で拡張子チェックを実施
    filter_suffix = ""
  }

  # Lambda関数の権限設定が完了してから作成
  depends_on = [aws_lambda_permission.s3_invoke]
}

# -----------------------------------------------------------------------------
# ライフサイクルルール（オプション）
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  # 古いバージョンの削除ルール
  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    # 非現行バージョンの削除（90日後）
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # 削除マーカーのクリーンアップ
    expiration {
      expired_object_delete_marker = true
    }
  }

  # 不完全なマルチパートアップロードの削除
  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# CORS設定（必要に応じて）
# -----------------------------------------------------------------------------
# NOTE: ブラウザから直接アップロードする場合は有効化
# resource "aws_s3_bucket_cors_configuration" "documents" {
#   bucket = aws_s3_bucket.documents.id
#
#   cors_rule {
#     allowed_headers = ["*"]
#     allowed_methods = ["GET", "PUT", "POST"]
#     allowed_origins = ["https://your-app.example.com"]
#     expose_headers  = ["ETag"]
#     max_age_seconds = 3000
#   }
# }
