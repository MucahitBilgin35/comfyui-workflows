#!/usr/bin/env bash
# Backs up the CURRENT /workspace/ComfyUI tree. Create your FULL Golden from a clean setup_full.sh instance.
set -Eeuo pipefail
COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
HF_REPO_ID="${HF_REPO_ID:-}"
HF_SNAPSHOT_FILE="${HF_SNAPSHOT_FILE:-comfyui_full_stable.tar.zst}"
TRANSFER_VENV="${TRANSFER_VENV:-/workspace/.comfy-transfer-venv}"
HF_CLI="$TRANSFER_VENV/bin/hf"
ARCHIVE="/workspace/$HF_SNAPSHOT_FILE"

[[ -n "$HF_REPO_ID" ]] || { echo "Set HF_REPO_ID first." >&2; exit 1; }
[[ -n "${HF_TOKEN:-}" ]] || { echo "Set HF_TOKEN first." >&2; exit 1; }
[[ -f "$COMFY_DIR/main.py" ]] || { echo "Missing $COMFY_DIR" >&2; exit 1; }

apt-get -o Acquire::Retries=3 update -qq
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y -qq --no-install-recommends \
  python3 python3-venv python3-pip zstd ca-certificates >/dev/null
if [[ ! -x "$HF_CLI" ]]; then
  python3 -m venv "$TRANSFER_VENV"
  "$TRANSFER_VENV/bin/python" -m pip install -q --upgrade pip wheel setuptools
  "$TRANSFER_VENV/bin/python" -m pip install -q --upgrade "huggingface_hub[hf_xet]>=1,<2"
fi

export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"
export HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-300}"
export HF_HUB_ETAG_TIMEOUT="${HF_HUB_ETAG_TIMEOUT:-30}"
export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
unset HF_HUB_ENABLE_HF_TRANSFER 2>/dev/null || true

find "$COMFY_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "$ARCHIVE"
cd /workspace

echo "Creating $HF_SNAPSHOT_FILE ..."
tar \
  --exclude='ComfyUI/output' \
  --exclude='ComfyUI/temp' \
  --exclude='ComfyUI/.cache' \
  --exclude='*.part' \
  --exclude='*.aria2' \
  -cf - ComfyUI | zstd -T0 -1 -o "$ARCHIVE"

echo "Snapshot size: $(du -h "$ARCHIVE" | awk '{print $1}')"
echo "Uploading to $HF_REPO_ID ..."
"$HF_CLI" upload "$HF_REPO_ID" "$ARCHIVE" "$HF_SNAPSHOT_FILE" --repo-type model --token "$HF_TOKEN"
echo "Upload complete."
