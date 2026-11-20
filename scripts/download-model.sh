#!/usr/bin/env bash
set -euo pipefail

# Download Qwen2.5-0.5B-Instruct (Q4_K_M GGUF) from ModelScope.
# Usage: ./scripts/download-model.sh [target-dir]

DIR="${1:-$HOME/models/qwen2.5-0.5b-instruct}"
FILE="$DIR/qwen2.5-0.5b-instruct-q4_k_m.gguf"
URL="https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf"

mkdir -p "$DIR"

echo "Downloading Qwen2.5-0.5B-Instruct to:"
echo "  $FILE"
echo "Source:"
echo "  $URL"

curl -L --fail --retry 5 --retry-delay 3 -C - -o "$FILE" "$URL"

echo "Done: $FILE"
