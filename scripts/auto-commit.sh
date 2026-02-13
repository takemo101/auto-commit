#!/usr/bin/env bash
set -euo pipefail

# === デフォルト設定 ===
MODEL=""
DEFAULT_MODELS=("llama3.2:1b" "qwen3:1.7b")
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
  echo "Error: ollama がインストールされていません。" >&2
  echo "" >&2
  echo "以下の方法でインストールしてください:" >&2
  echo "" >&2
  echo "  macOS:   brew install ollama" >&2
  echo "  Linux:   curl -fsSL https://ollama.com/install.sh | sh" >&2
  echo "  その他:  https://ollama.com/download" >&2
  echo "" >&2
  echo "インストール後、モデルをダウンロードしてください:" >&2
  echo "  ollama pull llama3.2:1b" >&2
  exit 1
fi

# === モデル自動選択（--model 未指定時） ===
if [[ -z "$MODEL" ]]; then
  AVAILABLE_MODELS=$(ollama list 2>/dev/null | awk 'NR>1{print $1}')
  for candidate in "${DEFAULT_MODELS[@]}"; do
    if echo "$AVAILABLE_MODELS" | grep -q "^${candidate}$"; then
      MODEL="$candidate"
      break
    fi
  done
  if [[ -z "$MODEL" ]]; then
    echo "Error: 利用可能なモデルが見つかりません。" >&2
    echo "以下のいずれかをダウンロードしてください:" >&2
    for m in "${DEFAULT_MODELS[@]}"; do
      echo "  ollama pull $m" >&2
    done
    exit 1
  fi
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
PROMPT="/no_think
Given the git diff below, write a single-line commit message.
Use Conventional Commits: type(scope): description
Allowed types: feat fix docs style refactor perf test build ci chore revert
Keep under 72 chars. Imperative mood. No period at end.
${LANG_INSTRUCTION}
Reply with ONLY the commit message line. No explanation, no formatting.

\`\`\`diff
${DIFF_FOR_PROMPT}
\`\`\`"

# === Ollama でメッセージ生成 ===
echo "🤖 Generating commit message with ${MODEL}..."
COMMIT_MSG=$(ollama run "$MODEL" "$PROMPT" 2>/dev/null)

# クリーンアップ: thinkタグ・思考テキスト除去、Conventional Commit 行を抽出
COMMIT_MSG=$(echo "$COMMIT_MSG" \
  | sed '/<think>/,/<\/think>/d' \
  | sed '/^Thinking/d' \
  | grep -E '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)' \
  | head -1 \
  | sed 's/^["`'"'"']*//;s/["`'"'"']*$//' \
  | sed 's/\.$//')

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
