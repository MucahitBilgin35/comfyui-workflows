#!/usr/bin/env bash
# Restore one FULL Golden snapshot to /workspace/ComfyUI, then start ComfyUI.
set -Eeuo pipefail
HF_REPO_ID="${HF_REPO_ID:-}"
HF_SNAPSHOT_FILE="${HF_SNAPSHOT_FILE:-comfyui_full_stable.tar.zst}"
DEST="${RESTORE_DEST:-/workspace}"
TRANSFER_VENV="${TRANSFER_VENV:-/workspace/.comfy-transfer-venv}"
HF_CLI="$TRANSFER_VENV/bin/hf"

[[ -n "$HF_REPO_ID" ]] || { echo "Set HF_REPO_ID first." >&2; exit 1; }
[[ -n "${HF_TOKEN:-}" ]] || { echo "Set HF_TOKEN first: export HF_TOKEN='hf_...'" >&2; exit 1; }

apt-get -o Acquire::Retries=3 update -qq
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y -qq --no-install-recommends \
  python3 python3-venv python3-pip zstd ca-certificates tmux >/dev/null

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

if [[ -e "$DEST/ComfyUI" && "${REPLACE_EXISTING:-0}" != "1" ]]; then
  echo "$DEST/ComfyUI already exists. Use a clean instance or set REPLACE_EXISTING=1." >&2
  exit 1
fi
[[ "${REPLACE_EXISTING:-0}" == "1" ]] && rm -rf "$DEST/ComfyUI"

STAGE="/workspace/.snapshot_restore"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DEST"

echo "Downloading $HF_REPO_ID/$HF_SNAPSHOT_FILE ..."
"$HF_CLI" download "$HF_REPO_ID" "$HF_SNAPSHOT_FILE" --repo-type model --local-dir "$STAGE" --token "$HF_TOKEN"
ARCHIVE="$STAGE/$HF_SNAPSHOT_FILE"
[[ -s "$ARCHIVE" ]] || { echo "Snapshot file not found: $ARCHIVE" >&2; exit 1; }

echo "Extracting to $DEST ..."
tar -I "zstd -T0 -d" -xf "$ARCHIVE" -C "$DEST"
rm -rf "$STAGE"

[[ -f "$DEST/ComfyUI/main.py" ]] || { echo "Restore finished but $DEST/ComfyUI/main.py is missing." >&2; exit 1; }

echo "Restore complete."
if [[ "${AUTO_START:-1}" == "1" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "$SCRIPT_DIR/start_comfyui.sh"
fi
