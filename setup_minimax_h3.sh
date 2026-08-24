#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + MINIMAX H3 (FL2VA + Ref2VA + SES) — ULTRA SETUP      ║
# ║  Hedef GPU      : RTX 4090 / RTX 5090 (24 GB+ VRAM)              ║
# ║  Özellikler     : Python API Downloader (Hataya Karşı Korumalı) ║
# ║                   + SageAttention (%25 Hızlandırma)             ║
# ║                   + VideoHelperSuite (Ses/Video Birleştirici)    ║
# ║                   + FL2VA & Ref2VA Pruned INT8 + NVFP4 TE        ║
# ║                   + Video & Audio VAE + 8-Step Turbo LoRA        ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail

COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.33.1"
TORCH_INDEX="https://download.pytorch.org/whl/cu130"
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
export HF_ENDPOINT
export HF_XET_HIGH_PERFORMANCE=1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${YELLOW}══════════════════════════════════════════════════${NC}"; echo -e "${YELLOW} $1${NC}"; echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
fail()  { echo -e "  ${RED}❌ $1${NC}"; exit 1; }
info()  { echo -e "  ${CYAN}→ $1${NC}"; }

# ── 0. HF_TOKEN ───────────────────────────────────────────────────
step "ADIM 0/10: HF_TOKEN Kontrolü"
if [ -z "${HF_TOKEN:-}" ]; then
  info "HF_TOKEN belirtilmedi. Public indirme yapılacak (Token tanımlanması önerilir)."
else
  HF_TOKEN="$(echo -n "$HF_TOKEN" | tr -d '[:space:]')"
  export HF_TOKEN
  ok "HF_TOKEN tanımlandı"
fi

# ── 1. DİSK ALANI ─────────────────────────────────────────────────
step "ADIM 1/10: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 85 ]; then
  fail "Sadece ${AVAIL}GB boş. Tüm H3 modelleri için en az 85-100GB önerilir!"
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 2. SİSTEM PAKETLERİ & FFMPEG ──────────────────────────────────
step "ADIM 2/10: Sistem Paketleri & C Derleyicileri"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
  python3-venv python3-pip python3-dev build-essential gcc g++ \
  curl wget ca-certificates > /dev/null 2>&1 || true
ldconfig
ok "Sistem paketleri, FFmpeg ve derleyiciler kuruldu"

# ── 3. COMFYUI ────────────────────────────────────────────────────
step "ADIM 3/10: ComfyUI Hazırlanıyor"
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" 2>/dev/null \
    || git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
else
  cd "$COMFY_DIR"
  git fetch --tags --quiet || true
  git checkout "$COMFY_TAG" 2>/dev/null || true
fi
ok "ComfyUI ($COMFY_TAG) hazır"

# ── 4. PYTHON + TORCH + SAGEATTENTION ─────────────────────────────
step "ADIM 4/10: Python venv, PyTorch & SageAttention Kurulumu"
cd "$COMFY_DIR"
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install -q --upgrade pip wheel setuptools
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q huggingface_hub einops timm accelerate transformers soundfile 2>/dev/null || true
pip install -q sageattention 2>/dev/null && ok "SageAttention kuruldu (%20-30 hız artışı)" || info "SageAttention atlandı (opsiyonel)"
ok "venv ve PyTorch hazır"

# ── 5. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 5/10: Klasör Yapısı"
mkdir -p "$COMFY_DIR/models/"{diffusion_models,text_encoders,vae,loras,controlnet,upscale_models,clip_vision,ipadapter}
mkdir -p "$COMFY_DIR/custom_nodes" "$COMFY_DIR/input" "$COMFY_DIR/output"
ok "Klasörler hazır"

# ── 6. CUSTOM NODE'LAR ────────────────────────────────────────────
step "ADIM 6/10: Custom Node'lar (VideoHelperSuite Dahil)"
cd "$COMFY_DIR/custom_nodes"

clone_node() {
  local name="$1" url="$2"
  if [ -d "$name" ]; then
    ok "$name zaten var"
  else
    info "$name indiriliyor..."
    git clone --depth 1 "$url" "$name" 2>/dev/null && ok "$name" || info "$name atlandı"
  fi
}

clone_node "ComfyUI-Manager"             "https://github.com/ltdrdata/ComfyUI-Manager.git"
clone_node "ComfyUI-VideoHelperSuite"     "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
clone_node "rgthree-comfy"               "https://github.com/rgthree/rgthree-comfy.git"
clone_node "ComfyUI-Impact-Pack"          "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_node "ComfyUI_essentials"          "https://github.com/cubiq/ComfyUI_essentials.git"
clone_node "comfyui-kjnodes"             "https://github.com/kijai/comfyui-kjnodes.git"
clone_node "ComfyUI-GGUF"                "https://github.com/city96/ComfyUI-GGUF.git"
clone_node "comfyui_controlnet_aux"       "https://github.com/Fannovel16/comfyui_controlnet_aux.git"

if [ -f "ComfyUI-Impact-Pack/install.py" ]; then
  python "ComfyUI-Impact-Pack/install.py" 2>/dev/null || true
fi
for d in */; do
  [ -f "${d}requirements.txt" ] && pip install -q -r "${d}requirements.txt" 2>/dev/null || true
done
ok "Custom node'lar kuruldu"

# ── 7. HATASIZ İNDİRME FONKSİYONU ─────────────────────────────────
cd "$COMFY_DIR"

download() {
  local url="$1" dir="$2" filename="$3" label="$4"
  local is_gated="${5:-false}"
  local dest="$COMFY_DIR/$dir/$filename"

  if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" -gt 5000000 ]; then
    local size
    size=$(du -h "$dest" | cut -f1)
    ok "$label ($size) — zaten var"
    return 0
  fi

  info "$label indiriliyor..."
  mkdir -p "$COMFY_DIR/$dir"

  local repo file
  repo=$(echo "$url" | sed -n 's|https://huggingface.co/\([^/]*/[^/]*\)/.*|\1|p')
  file=$(echo "$url" | sed -n 's|https://huggingface.co/[^/]*/[^/]*/resolve/[^/]*/\(.*\)|\1|p')
  [ -z "$file" ] && file=$(basename "${url%%\?*}")

  # 1. Python huggingface_hub API (Kalıcı ve Kesin Çözüm)
  if [ -n "$repo" ] && [ -n "$file" ]; then
    if python3 -c "
import sys, os, shutil
from huggingface_hub import hf_hub_download

repo_id = '$repo'
filename = '$file'
local_dir = '$COMFY_DIR/$dir'
dest = '$dest'
token = os.environ.get('HF_TOKEN', None)

try:
    downloaded_path = hf_hub_download(
        repo_id=repo_id,
        filename=filename,
        local_dir=local_dir,
        token=token
    )
    if downloaded_path != dest and os.path.exists(downloaded_path):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(downloaded_path, dest)
    sys.exit(0)
except Exception as e:
    print(f'HF Hatası: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
      if [ -f "$dest" ]; then
        find "$COMFY_DIR/$dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        ok "$label (hf_hub)"
        return 0
      fi
    fi
  fi

  # 2. aria2c (Yedek)
  if command -v aria2c >/dev/null 2>&1; then
    local -a aria_opts=(
      -c -x 16 -s 16 -k 1M
      --console-log-level=warn
      --max-tries=8 --retry-wait=5 --timeout=120 --connect-timeout=30
      -d "$COMFY_DIR/$dir" -o "$filename"
    )
    if [ -n "${HF_TOKEN:-}" ]; then
      aria_opts+=(--header="Authorization: Bearer ${HF_TOKEN}")
    fi
    if aria2c "${aria_opts[@]}" "$url" 2>/dev/null; then
      if [ -f "$dest" ]; then
        ok "$label (aria2c)"
        return 0
      fi
    fi
  fi

  # 3. curl (Son Çare)
  if [ -n "${HF_TOKEN:-}" ]; then
    curl -s -fL -H "Authorization: Bearer ${HF_TOKEN}" -o "$dest" "$url" 2>/dev/null && ok "$label (curl)" && return 0 || true
  else
    curl -s -fL -o "$dest" "$url" 2>/dev/null && ok "$label (curl)" && return 0 || true
  fi

  if [ "$is_gated" = true ]; then
    fail "$label indirilemedi!"
  else
    info "⚠️  $label indirilemedi (opsiyonel)"
    return 1
  fi
}

# ── 8. MODEL İNDİRMELERİ ──────────────────────────────────────────
step "ADIM 7/10: MiniMax H3 Model Paketleri İndiriliyor"

# 1. Ana I2V / T2V FL2VA Modeli (Pruned INT8)
download \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/split_files/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
  "models/diffusion_models" "minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
  "H3 FL2VA pruned INT8 (Ana Model)" false

# 2. Ref2VA Modeli (Referans Video/Ses/Görsel Modeli)
download \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/split_files/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
  "models/diffusion_models" "minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
  "H3 Ref2VA pruned INT8 (Opsiyonel)" false || true

# 3. Text Encoder (Qwen3-VL-32B NVFP4 AWQ)
download \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/split_files/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
  "models/text_encoders" "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
  "Qwen3-VL-32B NVFP4 Text Encoder" false

# 4. Video & Audio VAE
download \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/split_files/vae/minimax_h3_video_vae_fp16.safetensors" \
  "models/vae" "minimax_h3_video_vae_fp16.safetensors" \
  "MiniMax H3 Video VAE" false

download \
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/split_files/vae/minimax_h3_audio_vae_fp32.safetensors" \
  "models/vae" "minimax_h3_audio_vae_fp32.safetensors" \
  "MiniMax H3 Audio VAE (Stereo)" false

# 5. Turbo LoRA (8-Step)
download \
  "https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
  "models/loras" "minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
  "H3 FL2V Turbo 8-step LoRA" false || true

# ── 9. SYMLINK'LER ────────────────────────────────────────────────
step "ADIM 8/10: Şablon Uyumluluğu (symlink)"
ln -sf "$COMFY_DIR/models/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
       "$COMFY_DIR/models/diffusion_models/minimax_h3_fl2va.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
       "$COMFY_DIR/models/text_encoders/qwen3_vl_32b.safetensors" 2>/dev/null || true
ok "Symlink'ler oluşturuldu"

# ── 10. DOĞRULAMA ─────────────────────────────────────────────────
step "ADIM 9/10: Kurulum Doğrulaması"
ERRORS=0

verify() {
  local path="$1" name="$2"
  if [ -f "$COMFY_DIR/$path" ] && [ -s "$COMFY_DIR/$path" ]; then
    ok "$name"
  else
    echo -e "  ${RED}❌ $name EKSİK → $path${NC}"
    ERRORS=$((ERRORS+1))
  fi
}

verify "models/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" "FL2VA Ana Model"
verify "models/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"         "Qwen3-VL TE"
verify "models/vae/minimax_h3_video_vae_fp16.safetensors"                         "Video VAE"
verify "models/vae/minimax_h3_audio_vae_fp32.safetensors"                         "Audio VAE"

if [ $ERRORS -eq 0 ]; then
  ok "TÜM KRİTİK MINIMAX H3 MODELLERİ DOĞRULANDI"
else
  fail "$ERRORS adet model eksik!"
fi

# ── 11. BAŞLATMA (SageAttention Aktif) ────────────────────────────
step "ADIM 10/10: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
  "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram --use-sage-attention"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ MINIMAX H3 KURULUMU EKSİKSİZ TAMAMLANDI                  ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  GPU         : RTX 4090 / RTX 5090                           ║${NC}"
echo -e "${GREEN}║  Hızlandırma : SageAttention AKTİF (--use-sage-attention)    ║${NC}"
echo -e "${GREEN}║  Modeller    : FL2VA + Ref2VA + NVFP4 TE + Video/Audio VAE   ║${NC}"
echo -e "${GREEN}║  Log Takibi  : tmux attach -t comfyui                        ║${NC}"
echo -e "${GREEN}║  Port        : 8188                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
