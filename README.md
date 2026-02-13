# auto-commit

Ollama のローカル LLM を使って、git のステージング済み変更差分からコミットメッセージを自動生成してコミットする [pi](https://github.com/badlogic/pi) スキルです。

## 前提条件

- [Ollama](https://ollama.com/) がインストール済みで起動していること
- モデルがダウンロード済みであること（デフォルト: `qwen3:1.7b`）

## インストール

スキルディレクトリにクローン:

```bash
# グローバル
git clone https://github.com/takemo101/auto-commit.git ~/.pi/agent/skills/auto-commit

# プロジェクト
git clone https://github.com/takemo101/auto-commit.git .pi/skills/auto-commit
```

## 使い方

### pi から

コミットを依頼すると自動的に発動します。または明示的に:

```
/skill:auto-commit
```

### 直接実行

```bash
git add -A
./scripts/auto-commit.sh                    # 日本語でコミット
./scripts/auto-commit.sh --dry-run          # プレビューのみ
./scripts/auto-commit.sh --lang en          # 英語でコミット
./scripts/auto-commit.sh --model qwen3:1.7b # モデル変更
```

## オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--model <name>` | 使用する Ollama モデル | `qwen3:1.7b` |
| `--dry-run` | コミットせずメッセージのみ表示 | off |
| `--lang <code>` | コミットメッセージの言語 | `ja` |

## ライセンス

MIT
