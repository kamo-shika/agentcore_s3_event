#!/bin/bash
# =============================================================================
# Docker イメージビルド＆ECRプッシュスクリプト
# =============================================================================
# 概要:
#   AgentCore Runtime用のDockerイメージをビルドし、ECRにプッシュする
#
# 使用方法:
#   ./scripts/build_and_push.sh [OPTIONS]
#
# オプション:
#   -r, --region    AWSリージョン（デフォルト: us-east-1）
#   -t, --tag       イメージタグ（デフォルト: latest）
#   -n, --no-cache  キャッシュを使用しない
#   -h, --help      ヘルプを表示
#
# 例:
#   ./scripts/build_and_push.sh
#   ./scripts/build_and_push.sh --tag v1.0.0
#   ./scripts/build_and_push.sh --region ap-northeast-1 --no-cache
# =============================================================================

set -e  # エラー時に即座に終了

# -----------------------------------------------------------------------------
# 定数・デフォルト値
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# デフォルト値
DEFAULT_REGION="us-east-1"
DEFAULT_TAG="latest"
NO_CACHE=""

# -----------------------------------------------------------------------------
# ヘルプメッセージ
# -----------------------------------------------------------------------------
show_help() {
    cat << EOF
使用方法: $0 [OPTIONS]

AgentCore Runtime用のDockerイメージをビルドし、ECRにプッシュします。

オプション:
  -r, --region REGION   AWSリージョン（デフォルト: $DEFAULT_REGION）
  -t, --tag TAG         イメージタグ（デフォルト: $DEFAULT_TAG）
  -n, --no-cache        Dockerビルドでキャッシュを使用しない
  -h, --help            このヘルプメッセージを表示

例:
  $0                           # デフォルト設定でビルド＆プッシュ
  $0 --tag v1.0.0              # 特定のタグでビルド
  $0 --region ap-northeast-1   # 東京リージョンにプッシュ
  $0 --no-cache                # キャッシュを使わずにビルド
EOF
}

# -----------------------------------------------------------------------------
# 引数解析
# -----------------------------------------------------------------------------
REGION="$DEFAULT_REGION"
TAG="$DEFAULT_TAG"

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -n|--no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "エラー: 不明なオプション: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# メイン処理
# -----------------------------------------------------------------------------
echo "============================================================"
echo "Docker イメージビルド＆ECRプッシュ"
echo "============================================================"
echo "リージョン: $REGION"
echo "タグ: $TAG"
echo "プロジェクトルート: $PROJECT_ROOT"
echo "============================================================"

# AWSアカウントIDを取得
echo ""
echo "[1/5] AWSアカウント情報を取得中..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "アカウントID: $ACCOUNT_ID"

# ECRリポジトリURLを構築
# NOTE: Terraformで作成したリポジトリ名を使用
#       デフォルト: strands-doc-summarizer-dev-agent
ECR_REPO_NAME="${ECR_REPO_NAME:-strands-doc-summarizer-dev-agent}"
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "ECRリポジトリ: $ECR_URL"

# ECRにログイン
echo ""
echo "[2/5] ECRにログイン中..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "ログイン成功！"

# プロジェクトルートに移動
cd "$PROJECT_ROOT"

# uv.lockが存在しない場合は作成
if [ ! -f "uv.lock" ]; then
    echo ""
    echo "[2.5/5] uv.lock を生成中..."
    uv lock
fi

# Dockerイメージをビルド
echo ""
echo "[3/5] Dockerイメージをビルド中..."
echo "プラットフォーム: linux/arm64"

docker build \
    --platform linux/arm64 \
    $NO_CACHE \
    -t "${ECR_URL}:${TAG}" \
    -f Dockerfile \
    .

echo "ビルド完了！"

# イメージサイズを表示
IMAGE_SIZE=$(docker images "${ECR_URL}:${TAG}" --format "{{.Size}}")
echo "イメージサイズ: $IMAGE_SIZE"

# ECRにプッシュ
echo ""
echo "[4/5] ECRにプッシュ中..."
docker push "${ECR_URL}:${TAG}"

echo "プッシュ完了！"

# イメージダイジェストを取得
echo ""
echo "[5/5] イメージ情報を取得中..."
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name "$ECR_REPO_NAME" \
    --image-ids imageTag="$TAG" \
    --region "$REGION" \
    --query 'imageDetails[0].imageDigest' \
    --output text)

echo ""
echo "============================================================"
echo "完了！"
echo "============================================================"
echo "イメージURL: ${ECR_URL}:${TAG}"
echo "ダイジェスト: $IMAGE_DIGEST"
echo ""
echo "次のステップ:"
echo "  1. AgentCore Runtimeを更新（既存の場合）:"
echo "     aws bedrock-agentcore-control update-agent-runtime \\"
echo "       --agent-runtime-id YOUR_RUNTIME_ID \\"
echo "       --agent-runtime-artifact containerConfiguration={containerUri=${ECR_URL}:${TAG}}"
echo ""
echo "  2. または Terraform で更新:"
echo "     cd terraform && terraform apply"
echo "============================================================"
