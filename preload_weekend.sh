#!/usr/bin/env bash
# Safe background preload: downloads Weekend-only model files into final ComfyUI model folders.
# Does NOT clone nodes, modify ComfyUI venv, or restart ComfyUI.
set -Eeuo pipefail
RAW_BASE="https://raw.githubusercontent.com/MucahitBilgin35/comfyui-workflows/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/_comfy_common.sh"
if [[ ! -f "$COMMON" ]]; then
  apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
  curl -fL --retry 5 --retry-delay 2 "$RAW_BASE/_comfy_common.sh" -o "$COMMON"
fi

if [[ "${1:-}" == "--background" ]]; then
  apt-get update -qq && apt-get install -y -qq tmux >/dev/null
  tmux kill-session -t comfy-preload-weekend 2>/dev/null || true
  tmux new-session -d -s comfy-preload-weekend "cd '$SCRIPT_DIR' && bash '$0' 2>&1 | tee /workspace/preload_weekend.log"
  echo "Weekend preload started in background."
  echo "Watch: tmux attach -t comfy-preload-weekend"
  echo "Log:   tail -f /workspace/preload_weekend.log"
  exit 0
fi

source "$COMMON"
preload_profile weekend
