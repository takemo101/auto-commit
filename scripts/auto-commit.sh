#!/usr/bin/env bash
set -euo pipefail

# === デフォルト設定 ===
MODEL="llama3.2:1b"
DRY_RUN=false
LANG_CODE="ja"
MAX_DIFF_CHARS=8000

# === 引数パース ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --lang)
      LANG_CODE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# === 前提チェック ===
if ! command -v ollama &>/dev/null; then
  echo "Error: ollama is not installed." >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# === ステージング確認 ===
STAGED_DIFF=$(git diff --cached --stat)
if [[ -z "$STAGED_DIFF" ]]; then
  echo "Error: no staged changes. Run 'git add' first." >&2
  exit 1
fi

echo "📋 Staged changes:"
echo "$STAGED_DIFF"
echo ""

# === diff 取得（サイズ制限付き） ===
FULL_DIFF=$(git diff --cached)
if [[ ${#FULL_DIFF} -gt $MAX_DIFF_CHARS ]]; then
  DIFF_FOR_PROMPT="${FULL_DIFF:0:$MAX_DIFF_CHARS}
... (truncated, total ${#FULL_DIFF} chars)"
else
  DIFF_FOR_PROMPT="$FULL_DIFF"
fi

# === 言語指示 ===
if [[ "$LANG_CODE" == "ja" ]]; then
  LANG_INSTRUCTION="Write the commit message in Japanese."
elif [[ "$LANG_CODE" == "en" ]]; then
  LANG_INSTRUCTION="Write the commit message in English."
else
  LANG_INSTRUCTION="Write the commit message in language code: $LANG_CODE."
fi

# === プロンプト構築 ===
PROMPT="You are a git commit message generator. Based on the following diff, generate a concise and descriptive conventional commit message.

Rules:
- Use conventional commit format: type(scope): description
- Types: feat, fix, refactor, docs, style, test, chore, build, ci, perf
- Keep the first line under 72 characters
- If needed, add a blank line then a brief body (2-3 lines max)
- Output ONLY the commit message, nothing else. No markdown, no quotes, no explanation.
- ${LANG_INSTRUCTION}

Diff:
${DIFF_FOR_PROMPT}"

# === Ollama でメッセージ生成 ===
echo "🤖 Generating commit message with ${MODEL}..."
COMMIT_MSG=$(ollama run "$MODEL" "$PROMPT" 2>/dev/null)

# クリーンアップ: 引用符除去、空行以降の余計な出力をカット、先頭行のみ使用
COMMIT_MSG=$(echo "$COMMIT_MSG" \
  | sed 's/^["`'"'"']*//;s/["`'"'"']*$//' \
  | awk '/^$/{exit} {print}' \
  | head -5 \
  | sed '/^$/d')

if [[ -z "$COMMIT_MSG" ]]; then
  echo "Error: failed to generate commit message." >&2
  exit 1
fi

echo ""
echo "📝 Generated commit message:"
echo "---"
echo "$COMMIT_MSG"
echo "---"
echo ""

# === コミット実行 ===
if [[ "$DRY_RUN" == true ]]; then
  echo "🔍 Dry run mode — no commit made."
else
  git commit -m "$COMMIT_MSG"
  echo ""
  echo "✅ Committed successfully."
fi
