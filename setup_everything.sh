#!/usr/bin/env bash
# RECOMMENDED stable one-click setup for normal learning sessions.
# Installs the useful stable toolbox, validates it, and starts ComfyUI.
# Experimental/large extras stay in setup_fluxDev1Extras.sh.
set -Eeuo pipefail
RAW_BASE="https://raw.githubusercontent.com/MucahitBilgin35/comfyui-workflows/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/_comfy_common.sh"
if [[ ! -f "$COMMON" ]]; then
  apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
  curl -fL --retry 5 --retry-delay 2 "$RAW_BASE/_comfy_common.sh" -o "$COMMON"
fi
source "$COMMON"
run_profile everything
