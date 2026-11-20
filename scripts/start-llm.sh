#!/usr/bin/env bash
set -euo pipefail

# Start an OpenAI compatible llama.cpp server for Trans.nvim.
# Usage: ./scripts/start-llm.sh [model-path]

MODEL="${1:-$HOME/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX="${CTX:-4096}"
THREADS="${THREADS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

# Locate llama-server: $LLAMA_SERVER, PATH, then ~/tools/llama/*/llama-server
SERVER="${LLAMA_SERVER:-}"
if [ -z "$SERVER" ]; then
    if command -v llama-server >/dev/null 2>&1; then
        SERVER="$(command -v llama-server)"
    else
        SERVER="$(find "$HOME/tools/llama" -maxdepth 2 -name llama-server -type f 2>/dev/null | head -n 1 || true)"
    fi
fi

if [ -z "$SERVER" ] || [ ! -x "$SERVER" ]; then
    echo "llama-server not found. Install llama.cpp first:" >&2
    echo "  sudo port install llama.cpp   # macOS (MacPorts)" >&2
    echo "  brew install llama.cpp        # macOS (Homebrew)" >&2
    echo "" >&2
    echo "Or download a prebuilt binary:" >&2
    echo "  https://github.com/ggml-org/llama.cpp/releases" >&2
    echo "Then set LLAMA_SERVER=/path/to/llama-server." >&2
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Model not found: $MODEL" >&2
    echo "Run ./scripts/download-model.sh first, or pass the model path as the first argument." >&2
    exit 1
fi

echo "Starting llama-server:"
echo "  binary: $SERVER"
echo "  model:  $MODEL"
echo "  url:    http://$HOST:$PORT/v1/chat/completions"

exec "$SERVER" -m "$MODEL" --host "$HOST" --port "$PORT" -c "$CTX" -t "$THREADS"
