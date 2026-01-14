# Terraform 規約

## 命名規則

- リソース名: `{project}_{resource_type}_{purpose}`
- すべてのリソースに `Project`, `Environment` タグを付与

## コメント

- HCLファイル内のコメントは日本語で記述
- ただし `description` 属性は英語（日本語非対応のため）

## ファイル構成

```
terraform/
├── main.tf                 # プロバイダー設定
├── variables.tf            # 変数定義
├── outputs.tf              # 出力値
├── s3.tf                   # S3バケット
├── lambda.tf               # Lambda関数
├── ecr.tf                  # ECRリポジトリ
├── agentcore_runtime.tf    # AgentCore Runtime
├── agentcore_memory.tf     # AgentCore Memory + Strategy
└── iam.tf                  # IAMロール・ポリシー
```
