#!/bin/bash
# 勉強記事の自動コミット。launchd から毎日呼ばれる。
# Coworkの定期タスクが docs/ に .md を書いたあとに走らせる。

set -uo pipefail

REPO="$HOME/repos/study-notes"
LOG="$HOME/Library/Logs/study-notes-commit.log"

exec >>"$LOG" 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="

cd "$REPO" || { echo "リポジトリが見つかりません: $REPO"; exit 1; }

# 一時ファイルを掃除
rm -f docs/2026/_write-test.md 2>/dev/null

# 一覧を再生成
{
  echo "# 勉強記事アーカイブ"
  echo
  echo "毎朝の勉強記事のバックアップ。原本はNotionの「勉強記事置き場」。"
  echo
  count=$(find docs -name '*.md' -not -name 'INDEX.md' | wc -l | tr -d ' ')
  echo "全 ${count} 件。"
  for year in $(ls -1r docs 2>/dev/null | grep -E '^[0-9]{4}$'); do
    echo
    echo "## ${year}年"
    echo
    for f in $(ls -1r "docs/$year"/*.md 2>/dev/null); do
      base=$(basename "$f")
      title=$(grep -m1 '^title:' "$f" | sed 's/^title:[[:space:]]*//; s/^"//; s/"$//')
      [ -z "$title" ] && title="$base"
      echo "- ${base:0:10} [${title}](${year}/${base})"
    done
  done
} > docs/INDEX.md

# 前回の異常終了で残ったロックを掃除（15分以上前のものだけ）
if [ -f .git/index.lock ] && [ -z "$(find .git/index.lock -mmin -15 2>/dev/null)" ]; then
  echo "古い index.lock を削除します"
  rm -f .git/index.lock
fi

# 変更がなければ何もしない
if ! git add -A; then
  echo "git add に失敗しました"
  exit 1
fi
if git diff --cached --quiet; then
  echo "変更なし"
  exit 0
fi

git -c user.name="Kaito" -c user.email="kaito@cloudnative.co.jp" \
  commit -m "docs: 勉強記事を追加（$(date '+%Y-%m-%d')）" || { echo "commit 失敗"; exit 1; }

if git push -u origin HEAD; then
  echo "push 成功"
else
  echo "push 失敗（次回に再試行される）"
  exit 1
fi
