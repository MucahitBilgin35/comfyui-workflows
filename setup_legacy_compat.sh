#!/usr/bin/env bash
# OPTIONAL compatibility layer for old workflows only.
# WAS is archived and can break newer ComfyUI frontends.
# SUPIR wrapper is maintenance-only; SUPIR also has non-commercial restrictions.
set -Eeuo pipefail
RAW_BASE="https://raw.githubusercontent.com/MucahitBilgin35/comfyui-workflows/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/_comfy_common.sh"
if [[ ! -f "$COMMON" ]]; then
  apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
  curl -fL --retry 5 --retry-delay 2 "$RAW_BASE/_comfy_common.sh" -o "$COMMON"
fi
source "$COMMON"

export INSTALL_WAS_NODE_SUITE="${INSTALL_WAS_NODE_SUITE:-1}"
export INSTALL_SUPIR_LEGACY="${INSTALL_SUPIR_LEGACY:-1}"
prepare_system
comfy_base_ready || die "ComfyUI base missing at $COMFY_DIR"
ensure_model_dirs
install_legacy_compat_nodes
install_node_requirements
install_legacy_compat_models
create_legacy_compat_symlinks
validate_minimal
[[ "${NO_START:-0}" == "1" ]] || start_comfy
