#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║ COMFYUI + FLUX.2 KLEIN 9B/4B — RICH SETUP (setup_klein.sh)     ║
# ║ Son Güncelleme : 2026 - Tam Düzeltilmiş Sürüm                   ║
# ║ Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM                 ║
# ║ İçerik         : GCC/C Derleyiciler + Florence2 + EsesImage      ║
# ║                + kjnodes + NAG + UltraSharpV2 + Enhancer LoRA    ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.33.1"
TORCH_INDEX="https://download.pytorch.org/whl/cu130"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_ENDPOINT

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${YELLOW}══════════════════════════════════════════════════${NC}"; echo -e "${YELLOW} $1${NC}"; echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"; }
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; exit 1; }
info() { echo -e "  ${CYAN}→ $1${NC}"; }

# ── 0. TOKEN KONTROLÜ ─────────────────────────────────────────────
step "ADIM 0/9: HF_TOKEN Kontrolü"
if [ -z "${HF_TOKEN:-}" ]; then
  fail "HF_TOKEN bulunamadı! 'export HF_TOKEN=hf_...' yapıp tekrar çalıştırın."
fi
HF_TOKEN="$(echo -n "$HF_TOKEN" | tr -d '[:space:]')"
export HF_TOKEN

CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${HF_TOKEN}" \
  "https://huggingface.co/api/models/black-forest-labs/FLUX.2-klein-9b-fp8" || echo "000")
if [ "$CODE" != "200" ]; then
  fail "Token gated modele erişemiyor (HTTP $CODE). https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8 adresinden lisansı onaylayın."
fi
ok "HF_TOKEN geçerli (HTTP 200)"

# ── 1. DİSK KONTROLÜ ──────────────────────────────────────────────
step "ADIM 1/9: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 60 ]; then
  fail "Sadece ${AVAIL}GB boş. Tam kurulum için en az 60GB önerilir!"
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 2. SİSTEM PAKETLERİ (C Derleyicileri & Python Header Dosyaları) ─
step "ADIM 2/9: Sistem Paketleri & C Derleyicileri"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
  python3-venv python3-pip python3-dev build-essential gcc g++ \
  curl wget ca-certificates > /dev/null 2>&1 || true
ldconfig
ok "Sistem paketleri ve C derleyicileri (gcc, g++, python3-dev) kuruldu"

# ── 3. COMFYUI ────────────────────────────────────────────────────
step "ADIM 3/9: ComfyUI Hazırlanıyor"
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" 2>/dev/null \
    || git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
else
  cd "$COMFY_DIR"
  git fetch --tags --quiet || true
  git checkout "$COMFY_TAG" 2>/dev/null || true
fi
ok "ComfyUI ($COMFY_TAG) hazır"

# ── 4. PYTHON + TORCH ─────────────────────────────────────────────
step "ADIM 4/9: Python venv ve PyTorch"
cd "$COMFY_DIR"
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install -q --upgrade pip wheel setuptools
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q huggingface_hub einops timm 2>/dev/null || true
pip install -q -U "huggingface_hub[cli]" 2>/dev/null || true
ok "venv, PyTorch ve temel kütüphaneler hazır"

# ── 5. KLASÖR YAPISI ──────────────────────────────────────────────
step "ADIM 5/9: Klasör Yapısı"
mkdir -p "$COMFY_DIR/models/"{diffusion_models,text_encoders,vae,loras,controlnet,upscale_models,clip_vision,ipadapter,xlabs/ipadapters}
mkdir -p "$COMFY_DIR/custom_nodes" "$COMFY_DIR/input" "$COMFY_DIR/output"
ok "Klasörler hazır"

# ── 6. CUSTOM NODE'LAR ────────────────────────────────────────────
step "ADIM 6/9: Custom Node'lar Kuruluyor"
cd "$COMFY_DIR/custom_nodes"

clone_node() {
  local name="$1" url="$2"
  if [ -d "$name" ]; then
    ok "$name zaten var"
  else
    info "$name indiriliyor..."
    git clone --depth 1 "$url" "$name" 2>/dev/null && ok "$name" || info "$name atlandı (repo yok/hata)"
  fi
}

clone_node "ComfyUI-Manager"              "https://github.com/ltdrdata/ComfyUI-Manager.git"
clone_node "rgthree-comfy"                "https://github.com/rgthree/rgthree-comfy.git"
clone_node "ComfyUI-Impact-Pack"          "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_node "ComfyUI-Pixaroma"             "https://github.com/pixaroma/ComfyUI-Pixaroma.git"
clone_node "ComfyUI-GGUF"                 "https://github.com/city96/ComfyUI-GGUF.git"
clone_node "comfyui_controlnet_aux"       "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
clone_node "ComfyUI_essentials"           "https://github.com/cubiq/ComfyUI_essentials.git"
clone_node "ComfyUI-EsesImageCompare"     "https://github.com/quasiblob/ComfyUI-EsesImageCompare.git"
clone_node "ComfyUI-Florence2"            "https://github.com/kijai/ComfyUI-Florence2.git"
clone_node "comfyui-kjnodes"              "https://github.com/kijai/comfyui-kjnodes.git"
clone_node "sd-perturbed-attention"       "https://github.com/pamparamm/sd-perturbed-attention.git"
clone_node "one-node-flux-2-klein"        "https://github.com/yanokusnir-ai/one-node-flux-2-klein.git"
clone_node "ComfyUI-Flux2Klein-Enhancer"  "https://github.com/capitan01R/ComfyUI-Flux2Klein-Enhancer.git"
clone_node "Comfyui-flux2klein-Lora-loader" "https://github.com/capitan01R/Comfyui-flux2klein-Lora-loader.git"

if [ -f "ComfyUI-Impact-Pack/install.py" ]; then
  python "ComfyUI-Impact-Pack/install.py" 2>/dev/null || true
fi
for d in */; do
  if [ -f "${d}requirements.txt" ]; then
    pip install -q -r "${d}requirements.txt" 2>/dev/null || true
  fi
done
ok "Custom node'lar kuruldu"

# ── 7. İNDİRME FONKSİYONU (Düzeltilmiş Header ve HF CLI) ──────────
cd "$COMFY_DIR"

download() {
  local url="$1" dir="$2" filename="$3" label="$4"
  local is_gated="${5:-false}"
  local dest="$COMFY_DIR/$dir/$filename"

  if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" -gt 10000000 ]; then
    local size
    size=$(du -h "$dest" | cut -f1)
    ok "$label ($size) — zaten var"
    return 0
  fi

  info "$label indiriliyor..."

  local repo file
  repo=$(echo "$url" | sed -n 's|https://huggingface.co/\([^/]*/[^/]*\)/.*|\1|p')
  file=$(basename "${url%%\?*}")

  # 1. Güncel 'hf download' ile dene
  if command -v hf >/dev/null 2>&1 && [ -n "$repo" ] && [ -n "$file" ]; then
    if hf download "$repo" "$file" --local-dir "$COMFY_DIR/$dir" --token "$HF_TOKEN" >/dev/null 2>&1; then
      if [ -f "$COMFY_DIR/$dir/$file" ] && [ "$file" != "$filename" ]; then
        mv -f "$COMFY_DIR/$dir/$file" "$dest" 2>/dev/null || true
      fi
      if [ -f "$dest" ]; then
        ok "$label (hf)"
        return 0
      fi
    fi
  fi

  # 2. Düzeltilmiş Aria2c ile dene (Dizi kullanarak header hatası engellendi)
  local auth_args=()
  if [ "$is_gated" = true ]; then
    auth_args=(--header="Authorization: Bearer ${HF_TOKEN}")
  fi

  if aria2c -c -x 16 -s 16 -k 1M --console-log-level=error \
    --max-tries=8 --retry-wait=4 --timeout=120 --connect-timeout=30 \
    "${auth_args[@]}" "$url" -d "$COMFY_DIR/$dir" -o "$filename" 2>/dev/null; then
    ok "$label (aria2c)"
    return 0
  fi

  # 3. Mirror (Sadece public modeller için)
  if [ "$is_gated" = false ]; then
    local mirror_url="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
    if aria2c -c -x 16 -s 16 -k 1M --console-log-level=error \
      "$mirror_url" -d "$COMFY_DIR/$dir" -o "$filename" 2>/dev/null; then
      ok "$label (mirror)"
      return 0
    fi
  fi

  info "⚠️  $label indirilemedi!"
  return 1
}

# ── 8. MODEL İNDİRMELERİ ──────────────────────────────────────────
step "ADIM 7/9: Model Paketleri İndiriliyor"

# 1. Ana Distilled 9B FP8 (GATED)
download \
  "https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors" \
  "models/diffusion_models" "flux-2-klein-9b-fp8.safetensors" \
  "Klein 9B Distilled FP8" true

# 2. Text Encoder (Qwen3-8B FP8)
download \
  "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
  "models/text_encoders" "qwen_3_8b_fp8mixed.safetensors" \
  "Qwen3-8B FP8 Text Encoder" false

# 3. VAE
download \
  "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
  "models/vae" "flux2-vae.safetensors" \
  "Flux2 VAE" false

# 4. Upscaler (UltraSharpV2)
download \
  "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.pth" \
  "models/upscale_models" "4x-UltraSharpV2.pth" \
  "4x-UltraSharpV2" false || true

# 5. Workflow Detay Enhancer LoRA (HF Mirror)
download \
  "https://huggingface.co/reverentelusarca/detail-enhancer-flux-klein-9b/resolve/main/klein_9b_enhancer_v2.safetensors" \
  "models/loras" "klein_9b_enhancer_v2.safetensors" \
  "Klein 9B Enhancer v2 LoRA" false || true

# ── 9. DOĞRULAMA ──────────────────────────────────────────────────
step "ADIM 8/9: Kurulum Doğrulaması"
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

verify "models/diffusion_models/flux-2-klein-9b-fp8.safetensors" "Klein 9B Distilled FP8"
verify "models/text_encoders/qwen_3_8b_fp8mixed.safetensors"     "Qwen3-8B Text Encoder"
verify "models/vae/flux2-vae.safetensors"                        "Flux2 VAE"
verify "models/upscale_models/4x-UltraSharpV2.pth"              "4x-UltraSharpV2 Upscaler"
verify "models/loras/klein_9b_enhancer_v2.safetensors"          "Enhancer LoRA"

if [ $ERRORS -eq 0 ]; then
  ok "TÜM MODELLER VE EKLENTİLER DOĞRULANDI"
else
  fail "$ERRORS adet kritik model eksik!"
fi

# ── 10. BAŞLATMA ──────────────────────────────────────────────────
step "ADIM 9/9: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
  "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FLUX.2 KLEIN RICH KURULUM EKSİKSİZ TAMAMLANDI            ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Log Takibi : tmux attach -t comfyui                         ║${NC}"
echo -e "${GREEN}║  Port       : 8188                                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
