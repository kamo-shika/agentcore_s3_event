#!/bin/bash
# =============================================================================
# Lambda関数パッケージングスクリプト
# =============================================================================
# 概要:
#   プロキシLambda関数用のZIPパッケージを作成する
#
# 使用方法:
#   ./scripts/package_lambda.sh [OPTIONS]
#
# オプション:
#   -o, --output    出力先ディレクトリ（デフォルト: .build）
#   -h, --help      ヘルプを表示
#
# 出力:
#   .build/lambda_proxy.zip
# =============================================================================

set -e  # エラー時に即座に終了

# -----------------------------------------------------------------------------
# 定数・デフォルト値
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# デフォルトの出力ディレクトリ
DEFAULT_OUTPUT_DIR=".build"

# -----------------------------------------------------------------------------
# ヘルプメッセージ
# -----------------------------------------------------------------------------
show_help() {
    cat << EOF
使用方法: $0 [OPTIONS]

プロキシLambda関数用のZIPパッケージを作成します。

オプション:
  -o, --output DIR   出力先ディレクトリ（デフォルト: $DEFAULT_OUTPUT_DIR）
  -h, --help         このヘルプメッセージを表示

例:
  $0                     # デフォルト設定でパッケージング
  $0 --output dist       # dist ディレクトリに出力
EOF
}

# -----------------------------------------------------------------------------
# 引数解析
# -----------------------------------------------------------------------------
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
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
echo "Lambda関数パッケージング"
echo "============================================================"
echo "プロジェクトルート: $PROJECT_ROOT"
echo "出力ディレクトリ: $OUTPUT_DIR"
echo "============================================================"

# プロジェクトルートに移動
cd "$PROJECT_ROOT"

# 出力ディレクトリを作成
echo ""
echo "[1/4] 出力ディレクトリを準備中..."
rm -rf "$OUTPUT_DIR/lambda_package"
mkdir -p "$OUTPUT_DIR/lambda_package"

# Lambda関数のコードをコピー
echo ""
echo "[2/4] Lambda関数コードをコピー中..."
cp lambda/proxy_handler.py "$OUTPUT_DIR/lambda_package/"

# requirements.txtがあれば依存関係をインストール
# NOTE: プロキシLambdaはboto3のみ使用（Lambdaランタイムに含まれる）
#       追加の依存関係がある場合はここでインストール
if [ -f "lambda/requirements.txt" ]; then
    echo ""
    echo "[2.5/4] 依存関係を確認中..."

    # requirements.txtの内容を確認
    if grep -qv "^#" lambda/requirements.txt | grep -qv "^boto3"; then
        echo "追加の依存関係があります。インストールします..."
        pip install \
            --target "$OUTPUT_DIR/lambda_package" \
            --quiet \
            -r lambda/requirements.txt
    else
        echo "boto3のみのため、追加インストールはスキップします"
    fi
fi

# ZIPファイルを作成
echo ""
echo "[3/4] ZIPファイルを作成中..."
cd "$OUTPUT_DIR/lambda_package"
zip -r ../lambda_proxy.zip . -x "*.pyc" -x "__pycache__/*"

# 結果を表示
echo ""
echo "[4/4] パッケージング完了！"
cd "$PROJECT_ROOT"

ZIP_SIZE=$(du -h "$OUTPUT_DIR/lambda_proxy.zip" | cut -f1)
ZIP_PATH="$PROJECT_ROOT/$OUTPUT_DIR/lambda_proxy.zip"

echo ""
echo "============================================================"
echo "完了！"
echo "============================================================"
echo "出力ファイル: $ZIP_PATH"
echo "ファイルサイズ: $ZIP_SIZE"
echo ""
echo "ZIPファイルの内容:"
unzip -l "$OUTPUT_DIR/lambda_proxy.zip"
echo ""
echo "次のステップ:"
echo "  Terraformでデプロイ:"
echo "    cd terraform && terraform apply"
echo ""
echo "  または手動でアップロード:"
echo "    aws lambda update-function-code \\"
echo "      --function-name strands-doc-summarizer-dev-proxy \\"
echo "      --zip-file fileb://$ZIP_PATH"
echo "============================================================"
