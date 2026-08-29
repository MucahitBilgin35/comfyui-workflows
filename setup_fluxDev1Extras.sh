#!/usr/bin/env bash
# OPTIONAL EXTRAS for the FLUX Dev learning workstation.
# Adds Florence2 + RMBG and SeedVR2 7B quality option.
# BFL Canny/Depth LoRAs are included as an opt-in because they are gated/licensed.
set -Eeuo pipefail
RAW_BASE="https://raw.githubusercontent.com/MucahitBilgin35/comfyui-workflows/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/_comfy_common.sh"
if [[ ! -f "$COMMON" ]]; then
  apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
  curl -fL --retry 5 --retry-delay 2 "$RAW_BASE/_comfy_common.sh" -o "$COMMON"
fi
source "$COMMON"
[[ -x "${COMFY_DIR:-/workspace/ComfyUI}/venv/bin/python" ]] || die "Base ComfyUI missing. Run setup_everything.sh first."
run_profile extras
