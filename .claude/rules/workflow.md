# Claude Code ワークフロールール

## 提案・改善要求への対応

ユーザーからの提案や改善要求を受けた場合：

1. **Plan モードで検討する**
   - `EnterPlanMode` を使用して計画モードに入る
   - 既存コードへの影響を調査する
   - 複数のアプローチがある場合は比較検討する
   - 計画ファイルに設計を記載し、承認を得てから実装する

2. **調査が必要な場合**
   - ドキュメント（Context7等）を確認する
   - 既存の実装パターンを確認する
   - 不明点はユーザーに確認する

## Git ブランチ運用

リポジトリの作業には **git worktree** を使用する：

```bash
# 新しい作業ブランチを worktree で作成
git worktree add ../agentcore_s3_event-feature-xxx feature/xxx

# 作業完了後に worktree を削除
git worktree remove ../agentcore_s3_event-feature-xxx
```

**利点:**
- メインの作業ディレクトリを汚さない
- 複数の作業を並行して進められる
- レビュー中のブランチを別途チェックアウト可能
