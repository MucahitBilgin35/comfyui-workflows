#!/usr/bin/env bash
# Shared installer library for MucahitBilgin35/comfyui-workflows
# Updated: 2026-08-29
# Target: Clore.ai Ubuntu, RTX 3090/4090, 64 GB+ system RAM

set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
COMFY_REF="${COMFY_REF:-v0.33.1}"
TORCH_INDEX="${TORCH_INDEX:-https://download.pytorch.org/whl/cu130}"
HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-/workspace/.cache/pip}"
SETUP_WARNINGS="${SETUP_WARNINGS:-/workspace/comfy_setup_warnings.log}"
export HF_HOME PIP_CACHE_DIR
export HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-300}"
export HF_HUB_ETAG_TIMEOUT="${HF_HUB_ETAG_TIMEOUT:-30}"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
unset HF_HUB_ENABLE_HF_TRANSFER 2>/dev/null || true

# Hugging Face recommends Xet high-performance mode for high-bandwidth machines
# with at least 64 GB RAM. Enable it automatically when RAM is sufficient.
MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
if [[ "${HF_XET_HIGH_PERFORMANCE:-auto}" == "auto" ]]; then
  if (( MEM_GB >= 60 )); then
    export HF_XET_HIGH_PERFORMANCE=1
  else
    export HF_XET_HIGH_PERFORMANCE=0
  fi
else
  export HF_XET_HIGH_PERFORMANCE
fi

log(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok(){ printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; printf '[WARN] %s\n' "$*" >> "$SETUP_WARNINGS"; }
die(){ printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

prepare_system() {
  log "System packages + fast-transfer tools"
  mkdir -p /workspace "$HF_HOME" "$PIP_CACHE_DIR"
  : > "$SETUP_WARNINGS"
  apt-get -o Acquire::Retries=3 update -qq
  DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y -qq --no-install-recommends \
    git git-lfs curl wget ca-certificates aria2 tmux ffmpeg zstd unzip \
    python3 python3-venv python3-pip libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    >/dev/null
  git lfs install --skip-repo >/dev/null 2>&1 || true
  ok "System ready | RAM ${MEM_GB} GB | HF_XET_HIGH_PERFORMANCE=${HF_XET_HIGH_PERFORMANCE}"
}

install_comfyui() {
  log "ComfyUI $COMFY_REF"
  if [[ -d "$COMFY_DIR/.git" ]]; then
    git -C "$COMFY_DIR" fetch --tags --prune
    git -C "$COMFY_DIR" checkout "$COMFY_REF"
  else
    rm -rf "$COMFY_DIR"
    git clone --depth=1 --branch "$COMFY_REF" --filter=blob:none \
      https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" || \
    git clone --depth=1 --branch "$COMFY_REF" \
      https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
  fi

  cd "$COMFY_DIR"
  [[ -d venv ]] || python3 -m venv venv
  source venv/bin/activate
  python -m pip install -U pip wheel setuptools
  # Current ComfyUI NVIDIA guidance uses stable PyTorch with CUDA 13.0.
  python -m pip install torch torchvision torchaudio --extra-index-url "$TORCH_INDEX"
  python -m pip install -r requirements.txt
  python -m pip install -U "huggingface_hub>=0.32"
  mkdir -p models/{diffusion_models,unet,text_encoders,clip,vae,loras,controlnet,upscale_models,clip_vision,ipadapter,pulid,insightface/models/antelopev2,style_models,ultralytics/bbox,ultralytics/segm,sam2,SEEDVR2,facerestore_models,checkpoints,xlabs/ipadapters,xlabs/loras,xlabs/controlnets}
  ok "ComfyUI ready @ $(git -C "$COMFY_DIR" rev-parse --short HEAD)"
}

clone_node() {
  local name="$1" url="$2"
  local dst="$COMFY_DIR/custom_nodes/$name"
  mkdir -p "$COMFY_DIR/custom_nodes"
  if [[ -d "$dst/.git" ]]; then
    ok "$name already present"
    return 0
  fi
  log "Node: $name"
  git clone --depth=1 --filter=blob:none "$url" "$dst" || git clone --depth=1 "$url" "$dst"
}

install_base_nodes() {
  clone_node "ComfyUI-Manager" "https://github.com/Comfy-Org/ComfyUI-Manager.git"
  clone_node "rgthree-comfy" "https://github.com/rgthree/rgthree-comfy.git"
  clone_node "ComfyUI-Custom-Scripts" "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
  clone_node "comfyui_controlnet_aux" "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
  clone_node "ComfyUI-Impact-Pack" "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  clone_node "ComfyUI_essentials" "https://github.com/cubiq/ComfyUI_essentials.git"
  clone_node "x-flux-comfyui" "https://github.com/XLabs-AI/x-flux-comfyui.git"
}

install_advanced_nodes() {
  clone_node "ComfyUI-KJNodes" "https://github.com/kijai/ComfyUI-KJNodes.git"
  clone_node "ComfyUI-Inpaint-CropAndStitch" "https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"
  clone_node "ComfyUI-segment-anything-2" "https://github.com/kijai/ComfyUI-segment-anything-2.git"
  clone_node "ComfyUI_PuLID_Flux_ll" "https://github.com/lldacing/ComfyUI_PuLID_Flux_ll.git"
  clone_node "ComfyUI-ReActor" "https://github.com/Gourieff/ComfyUI-ReActor.git"
  clone_node "ComfyUI_UltimateSDUpscale" "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
  clone_node "ComfyUI-IC-Light" "https://github.com/kijai/ComfyUI-IC-Light.git"
  clone_node "ComfyUI-SeedVR2_VideoUpscaler" "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"

  # These old packages are deliberately not installed by default:
  # - WAS Node Suite: archived in 2025.
  # - ComfyUI_IPAdapter_plus: maintenance-only since 2025; FLUX path here is x-flux.
  # - ComfyUI-SUPIR wrapper: SUPIR is now in ComfyUI core.
  if [[ "${INSTALL_LEGACY_IPADAPTER_PLUS:-0}" == "1" ]]; then
    clone_node "ComfyUI_IPAdapter_plus" "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
  fi
}

install_node_requirements() {
  log "Custom-node dependencies"
  source "$COMFY_DIR/venv/bin/activate"
  local req
  for req in "$COMFY_DIR"/custom_nodes/*/requirements.txt; do
    [[ -f "$req" ]] || continue
    echo "Installing $(basename "$(dirname "$req")") requirements"
    if ! python -m pip install --prefer-binary -r "$req"; then
      warn "Dependency install failed: $req (setup continues; inspect validation/log)"
    fi
  done
  if [[ -f "$COMFY_DIR/custom_nodes/x-flux-comfyui/setup.py" ]]; then
    if ! (cd "$COMFY_DIR/custom_nodes/x-flux-comfyui" && python setup.py); then
      warn "x-flux setup.py failed"
    fi
  fi
  if [[ -d "$COMFY_DIR/custom_nodes/ComfyUI_PuLID_Flux_ll" ]]; then
    python -m pip install --prefer-binary --no-deps facenet-pytorch || warn "facenet-pytorch helper failed"
  fi
}

hf_file() {
  local repo="$1" remote="$2" target="$3" desc="$4"
  mkdir -p "$(dirname "$target")"
  if [[ -s "$target" ]]; then ok "$desc already present"; return 0; fi

  log "$desc"
  local stage="/workspace/.hf_stage_${RANDOM}_${RANDOM}"
  mkdir -p "$stage"
  local args=(download "$repo" "$remote" --local-dir "$stage")
  [[ -n "${HF_TOKEN:-}" ]] && args+=(--token "$HF_TOKEN")

  if hf "${args[@]}"; then
    if [[ -s "$stage/$remote" ]]; then
      mv "$stage/$remote" "$target"
      rm -rf "$stage"
      ok "$desc"
      return 0
    fi
  fi

  warn "hf_xet path failed for $desc; trying aria2 direct fallback"
  rm -rf "$stage"
  local url="https://huggingface.co/${repo}/resolve/main/${remote}"
  local aria=(aria2c -c -x 16 -s 16 -k 4M --file-allocation=none --max-tries=12 --retry-wait=3 --timeout=90 --connect-timeout=20 --allow-overwrite=true --auto-file-renaming=false)
  [[ -n "${HF_TOKEN:-}" ]] && aria+=(--header="Authorization: Bearer ${HF_TOKEN}")
  "${aria[@]}" "$url" -d "$(dirname "$target")" -o "$(basename "$target")"
  [[ -s "$target" ]] || die "$desc download failed"
  ok "$desc"
}

url_file() {
  local url="$1" target="$2" desc="$3"
  mkdir -p "$(dirname "$target")"
  [[ -s "$target" ]] && { ok "$desc already present"; return 0; }
  log "$desc"
  aria2c -c -x 16 -s 16 -k 4M --file-allocation=none --max-tries=12 --retry-wait=3 \
    --timeout=90 --connect-timeout=20 --allow-overwrite=true --auto-file-renaming=false \
    "$url" -d "$(dirname "$target")" -o "$(basename "$target")"
}

install_core_models() {
  hf_file "Kijai/flux-fp8" "flux1-dev-fp8.safetensors" "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" "FLUX.1 Dev FP8"
  hf_file "comfyanonymous/flux_text_encoders" "clip_l.safetensors" "$COMFY_DIR/models/text_encoders/clip_l.safetensors" "CLIP-L"
  hf_file "comfyanonymous/flux_text_encoders" "t5xxl_fp8_e4m3fn.safetensors" "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" "T5-XXL FP8"
  hf_file "camenduru/FLUX.1-dev" "ae.safetensors" "$COMFY_DIR/models/vae/ae.safetensors" "FLUX VAE"
  ln -sfn "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" "$COMFY_DIR/models/unet/flux1-dev-fp8.safetensors"
  ln -sfn "$COMFY_DIR/models/text_encoders/clip_l.safetensors" "$COMFY_DIR/models/clip/clip_l.safetensors"
  ln -sfn "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" "$COMFY_DIR/models/clip/t5xxl_fp8_e4m3fn.safetensors"
}

install_lora_models() {
  hf_file "XLabs-AI/flux-lora-collection" "realism_lora_comfy_converted.safetensors" "$COMFY_DIR/models/loras/flux_realism_comfy_converted.safetensors" "Realism LoRA (Comfy converted)"
  hf_file "XLabs-AI/flux-lora-collection" "anime_lora_comfy_converted.safetensors" "$COMFY_DIR/models/loras/flux_anime_comfy_converted.safetensors" "Anime LoRA (Comfy converted)"
  hf_file "XLabs-AI/flux-lora-collection" "art_lora_comfy_converted.safetensors" "$COMFY_DIR/models/loras/flux_art_comfy_converted.safetensors" "Art LoRA (Comfy converted)"
  hf_file "XLabs-AI/flux-lora-collection" "mjv6_lora_comfy_converted.safetensors" "$COMFY_DIR/models/loras/flux_mjv6_comfy_converted.safetensors" "MJv6 LoRA (Comfy converted)"
  hf_file "XLabs-AI/flux-lora-collection" "scenery_lora_comfy_converted.safetensors" "$COMFY_DIR/models/loras/flux_scenery_comfy_converted.safetensors" "Scenery LoRA (Comfy converted)"
  hf_file "Shakker-Labs/FLUX.1-dev-LoRA-add-details" "FLUX-dev-lora-add_details.safetensors" "$COMFY_DIR/models/loras/flux_add_details.safetensors" "Add Details LoRA"
  hf_file "alvdansen/flux_film_foto" "araminta_k_flux_film_foto.safetensors" "$COMFY_DIR/models/loras/flux_film_foto.safetensors" "Film Foto LoRA"
  hf_file "strangerzonehf/Flux-Super-Realism-LoRA" "super-realism.safetensors" "$COMFY_DIR/models/loras/flux_super_realism.safetensors" "Super Realism LoRA"
  hf_file "XLabs-AI/flux-RealismLora" "lora.safetensors" "$COMFY_DIR/models/xlabs/loras/flux_realism_xlabs_raw.safetensors" "Realism LoRA (XLabs raw)"
}

install_control_models() {
  hf_file "Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro" "diffusion_pytorch_model.safetensors" "$COMFY_DIR/models/controlnet/flux-dev-controlnet-union-pro.safetensors" "ControlNet Union Pro"
  hf_file "XLabs-AI/flux-controlnet-depth-v3" "flux-depth-controlnet-v3.safetensors" "$COMFY_DIR/models/xlabs/controlnets/flux-depth-controlnet-v3.safetensors" "XLabs Depth ControlNet"
  hf_file "XLabs-AI/flux-controlnet-canny-v3" "flux-canny-controlnet-v3.safetensors" "$COMFY_DIR/models/xlabs/controlnets/flux-canny-controlnet-v3.safetensors" "XLabs Canny ControlNet"
  hf_file "XLabs-AI/flux-controlnet-hed-v3" "flux-hed-controlnet-v3.safetensors" "$COMFY_DIR/models/xlabs/controlnets/flux-hed-controlnet-v3.safetensors" "XLabs HED ControlNet"
}

install_identity_models() {
  hf_file "openai/clip-vit-large-patch14" "model.safetensors" "$COMFY_DIR/models/clip_vision/clip-vit-large-patch14.safetensors" "CLIP ViT-L/14 for XLabs IP-Adapter"
  hf_file "XLabs-AI/flux-ip-adapter" "ip_adapter.safetensors" "$COMFY_DIR/models/xlabs/ipadapters/flux-ip-adapter.safetensors" "XLabs FLUX IP-Adapter"
  ln -sfn "$COMFY_DIR/models/xlabs/ipadapters/flux-ip-adapter.safetensors" "$COMFY_DIR/models/ipadapter/flux-ip-adapter.safetensors"
  hf_file "guozinan/PuLID" "pulid_flux_v0.9.1.safetensors" "$COMFY_DIR/models/pulid/pulid_flux_v0.9.1.safetensors" "PuLID Flux v0.9.1"
  hf_file "QuanSun/EVA-CLIP" "EVA02_CLIP_L_336_psz14_s6B.pt" "$COMFY_DIR/models/clip/EVA02_CLIP_L_336_psz14_s6B.pt" "EVA-CLIP for PuLID"
  if [[ ! -s "$COMFY_DIR/models/insightface/models/antelopev2/1k3d68.onnx" ]]; then
    local zip="/workspace/antelopev2.zip"
    hf_file "MonsterMMORPG/tools" "antelopev2.zip" "$zip" "Antelopev2 bundle"
    unzip -qo "$zip" -d "$COMFY_DIR/models/insightface/models"
    rm -f "$zip"
    if [[ -d "$COMFY_DIR/models/insightface/models/antelopev2/antelopev2" ]]; then
      mv "$COMFY_DIR/models/insightface/models/antelopev2/antelopev2"/* "$COMFY_DIR/models/insightface/models/antelopev2/"
      rmdir "$COMFY_DIR/models/insightface/models/antelopev2/antelopev2" 2>/dev/null || true
    fi
  fi
}

install_rich_models() {
  hf_file "comfyanonymous/flux_text_encoders" "t5xxl_fp16.safetensors" "$COMFY_DIR/models/text_encoders/t5xxl_fp16.safetensors" "T5-XXL FP16"
  ln -sfn "$COMFY_DIR/models/text_encoders/t5xxl_fp16.safetensors" "$COMFY_DIR/models/clip/t5xxl_fp16.safetensors"
  hf_file "Comfy-Org/Flux1-Redux-Dev" "flux1-redux-dev.safetensors" "$COMFY_DIR/models/style_models/flux1-redux-dev.safetensors" "FLUX Redux"
  hf_file "Comfy-Org/sigclip_vision_384" "sigclip_vision_patch14_384.safetensors" "$COMFY_DIR/models/clip_vision/sigclip_vision_patch14_384.safetensors" "SigCLIP Vision"
  hf_file "lokCX/4x-Ultrasharp" "4x-UltraSharp.pth" "$COMFY_DIR/models/upscale_models/4x-UltraSharp.pth" "4x-UltraSharp"
  hf_file "uwg/upscaler" "ESRGAN/4x_NMKD-Siax_200k.pth" "$COMFY_DIR/models/upscale_models/4x_NMKD-Siax_200k.pth" "4x NMKD-Siax"
  hf_file "numz/SeedVR2_comfyUI" "seedvr2_ema_3b_fp8_e4m3fn.safetensors" "$COMFY_DIR/models/SEEDVR2/seedvr2_ema_3b_fp8_e4m3fn.safetensors" "SeedVR2 3B FP8"
  hf_file "numz/SeedVR2_comfyUI" "ema_vae_fp16.safetensors" "$COMFY_DIR/models/SEEDVR2/ema_vae_fp16.safetensors" "SeedVR2 VAE FP16"
  hf_file "Bingsu/adetailer" "face_yolov8m.pt" "$COMFY_DIR/models/ultralytics/bbox/face_yolov8m.pt" "Face YOLO v8m"
  hf_file "Bingsu/adetailer" "face_yolov8n.pt" "$COMFY_DIR/models/ultralytics/bbox/face_yolov8n.pt" "Face YOLO v8n"
}

install_editing_models() {
  hf_file "Kijai/sam2-safetensors" "sam2_hiera_large.safetensors" "$COMFY_DIR/models/sam2/sam2_hiera_large.safetensors" "SAM2 Hiera Large"
  url_file "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx" "$COMFY_DIR/models/insightface/inswapper_128.onnx" "ReActor inswapper_128" || true
  url_file "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.4/GFPGANv1.4.pth" "$COMFY_DIR/models/facerestore_models/GFPGANv1.4.pth" "GFPGAN v1.4" || true
  hf_file "lllyasviel/ic-light" "iclight_sd15_fc.safetensors" "$COMFY_DIR/models/unet/IC-Light/iclight_sd15_fc.safetensors" "IC-Light FC (SD1.5 pipeline)"
  hf_file "lllyasviel/ic-light" "iclight_sd15_fbc.safetensors" "$COMFY_DIR/models/unet/IC-Light/iclight_sd15_fbc.safetensors" "IC-Light FBC (SD1.5 pipeline)"

  # FLUX Fill is gated/licensed. Install only after the user explicitly opts in.
  if [[ "${ACCEPT_FLUX_DEV_LICENSE:-0}" == "1" ]]; then
    [[ -n "${HF_TOKEN:-}" ]] || warn "ACCEPT_FLUX_DEV_LICENSE=1 but HF_TOKEN is not set; FLUX Fill may fail to download"
    hf_file "Comfy-Org/flux1-dev" "split_files/diffusion_models/flux1-fill-dev.safetensors" "$COMFY_DIR/models/diffusion_models/flux1-fill-dev.safetensors" "FLUX.1 Fill Dev"
  else
    warn "FLUX.1 Fill Dev skipped (set ACCEPT_FLUX_DEV_LICENSE=1 after accepting its license)"
  fi
}

validate_minimal() {
  log "Validation"
  local missing=0
  for f in \
    "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" \
    "$COMFY_DIR/models/text_encoders/clip_l.safetensors" \
    "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" \
    "$COMFY_DIR/models/vae/ae.safetensors"; do
    [[ -s "$f" ]] && ok "$(basename "$f")" || { warn "Missing $f"; missing=$((missing+1)); }
  done
  if [[ -s "$COMFY_DIR/models/loras/flux_realism.safetensors" ]]; then
    warn "Legacy ambiguous flux_realism.safetensors found. Updated scripts use explicit converted/raw filenames."
  fi
  (( missing == 0 )) || die "$missing critical files missing"
}

start_comfy() {
  log "Starting ComfyUI"
  source "$COMFY_DIR/venv/bin/activate"
  tmux kill-session -t comfyui 2>/dev/null || true
  # Stable performance default for 24 GB GPUs: keep 1 GB headroom and let current
  # ComfyUI DynamicVRAM/async offload manage complex workflows. Do not use --fast:
  # ComfyUI labels it experimental and potentially quality-degrading.
  local args="${COMFY_LAUNCH_ARGS:---listen 0.0.0.0 --port 8188 --reserve-vram 1.0}"
  tmux new-session -d -s comfyui "cd '$COMFY_DIR' && source venv/bin/activate && python main.py $args 2>&1 | tee /workspace/comfyui.log"
  ok "ComfyUI started | tmux attach -t comfyui | log /workspace/comfyui.log"
}

run_profile() {
  local profile="$1"
  prepare_system
  if [[ "$profile" == "extras" ]]; then
    [[ -x "$COMFY_DIR/venv/bin/python" ]] || die "Base ComfyUI missing. Run setup_full.sh or setup_weekend.sh first."
    source "$COMFY_DIR/venv/bin/activate"
    python -m pip install -U "huggingface_hub>=0.32" >/dev/null
  else
    install_comfyui
  fi

  case "$profile" in
    full)
      install_base_nodes
      install_node_requirements
      install_core_models
      install_lora_models
      install_control_models
      install_identity_models
      ;;
    weekend)
      install_base_nodes
      install_advanced_nodes
      install_node_requirements
      install_core_models
      install_lora_models
      install_control_models
      install_identity_models
      install_rich_models
      install_editing_models
      ;;
    extras)
      install_advanced_nodes
      install_node_requirements
      install_identity_models
      install_rich_models
      install_editing_models
      ;;
    everything)
      install_base_nodes
      install_advanced_nodes
      install_node_requirements
      install_core_models
      install_lora_models
      install_control_models
      install_identity_models
      install_rich_models
      install_editing_models
      ;;
    *) die "Unknown profile: $profile" ;;
  esac

  validate_minimal
  start_comfy

  echo
  echo "============================================================"
  echo " SETUP FINISHED: $profile"
  echo "============================================================"
  if [[ -s "$SETUP_WARNINGS" ]]; then
    echo "Warnings were recorded in: $SETUP_WARNINGS"
  fi
  echo "ComfyUI is already running. You do NOT need to type the tmux start commands manually."
  echo "To view it: tmux attach -t comfyui"
}
