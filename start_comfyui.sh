#!/usr/bin/env bash
set -Eeuo pipefail
COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
[[ -x "$COMFY_DIR/venv/bin/python" ]] || { echo "Missing ComfyUI venv at $COMFY_DIR" >&2; exit 1; }
source "$COMFY_DIR/venv/bin/activate"
python - <<'PY'
import torch
print('CUDA:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('GPU :', torch.cuda.get_device_name(0))
PY

tmux kill-session -t comfyui 2>/dev/null || true
ARGS="${COMFY_LAUNCH_ARGS:---listen 0.0.0.0 --port 8188 --reserve-vram 1.0}"
tmux new-session -d -s comfyui "cd '$COMFY_DIR' && source venv/bin/activate && python main.py $ARGS 2>&1 | tee /workspace/comfyui.log"
echo "ComfyUI started."
echo "View log: tmux attach -t comfyui"
