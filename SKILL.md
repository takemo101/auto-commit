---
name: auto-commit
description: Ollamaを使ってgitのステージング済み変更からコミットメッセージを自動生成し、コミットする。git commitを求められたときに使う。
metadata:
  author: takemo101
  github: https://github.com/takemo101
  repository: https://github.com/takemo101/auto-commit
---

# Auto Commit

Ollama のローカル LLM を使って、ステージング済みの変更差分からコミットメッセージを自動生成してコミットするスキル。

## 前提条件

- `ollama` がインストール済みで起動していること
- Ollama にモデルがダウンロード済みであること（デフォルト: `llama3.2:1b`）

## 使い方

### 1. 変更をステージングする

```bash
git add <files>
# または
git add -A
```

### 2. スクリプトを実行する

```bash
# デフォルト（llama3.2:1b モデル）
./scripts/auto-commit.sh

# モデルを指定
./scripts/auto-commit.sh --model qwen3:1.7b

# ドライラン（コミットメッセージを生成するだけでコミットしない）
./scripts/auto-commit.sh --dry-run

# 日本語でコミットメッセージを生成
./scripts/auto-commit.sh --lang ja
```

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--model <name>` | 使用するOllamaモデル | `llama3.2:1b` |
| `--dry-run` | コミットせずメッセージのみ表示 | off |
| `--lang <code>` | コミットメッセージの言語 | `ja` |

## エージェントへの指示

1. ユーザーがコミットを依頼したら、`./scripts/auto-commit.sh` を実行する
   - ステージング済みの変更がなければ、スクリプトが自動で全変更をステージングする
2. `--dry-run` で生成されたメッセージをユーザーに見せ、確認を取ってから本コミットしてもよい
