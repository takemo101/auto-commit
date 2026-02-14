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

# === ステージング確認（未ステージなら全てステージ） ===
STAGED_DIFF=$(git diff --cached --stat)
if [[ -z "$STAGED_DIFF" ]]; then
  # ステージされていない変更があれば全てステージ
  if [[ -n $(git status --porcelain) ]]; then
    echo "📦 No staged changes. Staging all changes..."
    git add -A
    STAGED_DIFF=$(git diff --cached --stat)
  fi
  # それでも空なら終了
  if [[ -z "$STAGED_DIFF" ]]; then
    echo "Error: no changes to commit." >&2
    exit 1
  fi
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
You must reply with exactly ONE line in this format:
type: description

Example outputs:
feat: ログインエンドポイントを追加
fix: nullポインタエラーを修正
refactor: CLI呼び出しをAPI呼び出しに変更

Allowed types: feat fix docs style refactor perf test build ci chore revert
Rules: under 72 chars, imperative mood, no period at end, NO scope in parentheses.
${LANG_INSTRUCTION}

IMPORTANT: Your reply must start with one of the allowed types. No other text.

\`\`\`diff
${DIFF_FOR_PROMPT}
\`\`\`"

# === Ollama モデルのプリロード ===
# 空プロンプトでモデルをメモリにロードさせる（トークン消費なし）
echo "🔄 Loading model ${MODEL}..."
PRELOAD_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 120 \
  http://localhost:11434/api/generate \
  -d "$(jq -n --arg model "$MODEL" \
    '{model: $model, stream: false}')" 2>/dev/null)

if [[ "$PRELOAD_RESPONSE" != "200" ]]; then
  echo "Warning: モデルのプリロードに失敗しました (HTTP ${PRELOAD_RESPONSE})" >&2
  echo "Ollama が起動しているか確認してください: ollama serve" >&2
fi

# === Ollama API でメッセージ生成（リトライ付き） ===
echo "🤖 Generating commit message with ${MODEL}..."
MAX_RETRIES=2
RETRY=0
API_RESPONSE=""

while [[ $RETRY -le $MAX_RETRIES ]]; do
  API_RESPONSE=$(curl -s --max-time 120 http://localhost:11434/api/generate \
    -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" \
      '{model: $model, prompt: $prompt, stream: false}')" 2>/dev/null)

  RESPONSE_TEXT=$(echo "$API_RESPONSE" | jq -r '.response // empty' 2>/dev/null)
  if [[ -n "$RESPONSE_TEXT" ]]; then
    break
  fi

  RETRY=$((RETRY + 1))
  if [[ $RETRY -le $MAX_RETRIES ]]; then
    echo "⏳ Retrying... (${RETRY}/${MAX_RETRIES})"
    sleep 2
  fi
done

COMMIT_MSG=$(echo "$API_RESPONSE" | jq -r '.response // empty')

# クリーンアップ: thinkタグ・思考テキスト除去
RAW_MSG="$COMMIT_MSG"
COMMIT_MSG=$(echo "$COMMIT_MSG" \
  | sed '/<think>/,/<\/think>/d' \
  | sed '/^Thinking/d' \
  | sed 's/^["`'"'"']*//;s/["`'"'"']*$//' \
  | sed '/^$/d')

# Conventional Commit 行を抽出
CC_LINE=$(echo "$COMMIT_MSG" | grep -E '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)' | head -1)
  # scope除去: type(scope): desc → type: desc
  CC_LINE=$(echo "$CC_LINE" | sed 's/^\([a-z]*\)([^)]*)/\1/')
if [[ -n "$CC_LINE" ]]; then
  COMMIT_MSG=$(echo "$CC_LINE" | sed 's/\.$//')
else
  # フォールバック: 先頭行を取得し chore: を付与
  FIRST_LINE=$(echo "$COMMIT_MSG" | head -1 | sed 's/\.$//')
  if [[ -n "$FIRST_LINE" ]]; then
    COMMIT_MSG="chore: ${FIRST_LINE}"
  fi
fi

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
