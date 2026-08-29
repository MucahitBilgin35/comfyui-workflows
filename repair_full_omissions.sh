#!/usr/bin/env bash
# Repairs assets that existed in the user's original setup_full.sh but were
# mistakenly omitted/moved in v2.1. Safe on an existing FULL snapshot/install:
# existing files/nodes are skipped.
set -Eeuo pipefail
RAW_BASE="https://raw.githubusercontent.com/MucahitBilgin35/comfyui-workflows/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/_comfy_common.sh"
if [[ ! -f "$COMMON" ]]; then
  apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
  curl -fL --retry 5 --retry-delay 2 "$RAW_BASE/_comfy_common.sh" -o "$COMMON"
fi
source "$COMMON"

prepare_system
comfy_base_ready || die "ComfyUI base missing at $COMFY_DIR"
ensure_model_dirs

log "Restoring original FULL assets omitted by v2.1"
clone_node "ComfyUI-Pixaroma" "https://github.com/pixaroma/ComfyUI-Pixaroma.git"
clone_node "ComfyUI_IPAdapter_plus" "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
install_node_requirements

hf_file "alimama-creative/FLUX.1-Turbo-Alpha" "diffusion_pytorch_model.safetensors" "$COMFY_DIR/models/loras/flux_turbo_alpha.safetensors" "FLUX Turbo Alpha"
install_full_utility_models
create_legacy_compat_symlinks

validate_minimal
if [[ "${NO_START:-0}" != "1" ]]; then
  start_comfy
fi

echo
echo "============================================================"
echo " ORIGINAL FULL REPAIR COMPLETE"
echo "============================================================"
echo "Restored: Pixaroma, IPAdapter Plus, FLUX Turbo Alpha,"
echo "          UltraSharp, SigCLIP, and legacy workflow symlinks."
echo "Existing files were not re-downloaded."
