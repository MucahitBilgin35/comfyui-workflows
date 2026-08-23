#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + KREA 2 TURBO FP8 — RICH SETUP (setup_krea2.sh)      ║
# ║  Son Güncelleme : 23 Ağustos 2026                               ║
# ║  Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM               ║
# ║  İçerik         : Turbo FP8 + Qwen3VL TE + Qwen VAE             ║
# ║                   + Style LoRA'lar + SeedVR2 + face/detail tools ║
# ║                   + Manager + Impact + Pixaroma + essentials     ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail

COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.33.1"
TORCH_INDEX="https://download.pytorch.org/whl/cu130"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_ENDPOINT
export HF_HUB_ENABLE_HF_TRANSFER=1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${YELLOW}══════════════════════════════════════════════════${NC}"; echo -e "${YELLOW} $1${NC}"; echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
fail()  { echo -e "  ${RED}❌ $1${NC}"; exit 1; }
info()  { echo -e "  ${CYAN}→ $1${NC}"; }

# ── 0. DİSK ───────────────────────────────────────────────────────
step "ADIM 0/9: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 45 ]; then
  fail "Sadece ${AVAIL}GB boş. Krea 2 rich paketi için en az 45GB önerilir!"
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 1. SİSTEM ─────────────────────────────────────────────────────
step "ADIM 1/9: Sistem Paketleri"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
  python3-venv python3-pip curl wget ca-certificates > /dev/null 2>&1 || true
ok "Sistem paketleri kuruldu"

# ── 2. COMFYUI ────────────────────────────────────────────────────
step "ADIM 2/9: ComfyUI"
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" 2>/dev/null \
    || git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
else
  cd "$COMFY_DIR"
  git fetch --tags --quiet || true
  git checkout "$COMFY_TAG" 2>/dev/null || true
fi
ok "ComfyUI ($COMFY_TAG) hazır"

# ── 3. VENV + TORCH ───────────────────────────────────────────────
step "ADIM 3/9: Python venv + PyTorch"
cd "$COMFY_DIR"
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install -q --upgrade pip wheel setuptools
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q huggingface_hub hf_transfer "huggingface_hub[cli]" 2>/dev/null || true
ok "venv + PyTorch (cu130) hazır"

# ── 4. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 4/9: Klasör Yapısı"
mkdir -p "$COMFY_DIR/models/"{diffusion_models,text_encoders,vae,loras,controlnet,upscale_models,clip_vision,ipadapter}
mkdir -p "$COMFY_DIR/custom_nodes" "$COMFY_DIR/input" "$COMFY_DIR/output"
ok "Klasörler hazır"

# ── 5. CUSTOM NODES ───────────────────────────────────────────────
step "ADIM 5/9: Custom Node'lar"
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

clone_node "ComfyUI-Manager"          "https://github.com/ltdrdata/ComfyUI-Manager.git"
clone_node "rgthree-comfy"            "https://github.com/rgthree/rgthree-comfy.git"
clone_node "ComfyUI-Impact-Pack"      "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_node "ComfyUI-Pixaroma"         "https://github.com/pixaroma/ComfyUI-Pixaroma.git"
clone_node "ComfyUI-GGUF"             "https://github.com/city96/ComfyUI-GGUF.git"
clone_node "comfyui_controlnet_aux"   "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
clone_node "ComfyUI_essentials"       "https://github.com/cubiq/ComfyUI_essentials.git"

if [ -f "ComfyUI-Impact-Pack/install.py" ]; then
  python "ComfyUI-Impact-Pack/install.py" 2>/dev/null || true
fi
for d in */; do
  [ -f "${d}requirements.txt" ] && pip install -q -r "${d}requirements.txt" 2>/dev/null || true
done
ok "Custom node'lar kuruldu"

# ── 6. İNDİRME FONKSİYONU ─────────────────────────────────────────
cd "$COMFY_DIR"

download() {
  local url="$1" dir="$2" filename="$3" label="$4"
  local dest="$COMFY_DIR/$dir/$filename"

  if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" -gt 5000000 ]; then
    local size
    size=$(du -h "$dest" | cut -f1)
    ok "$label ($size) — zaten var"
    return 0
  fi

  info "$label indiriliyor..."

  # 1) huggingface-cli
  if command -v huggingface-cli >/dev/null 2>&1; then
    local repo file
    repo=$(echo "$url" | sed -n 's|https://huggingface.co/\([^/]*/[^/]*\)/.*|\1|p')
    file=$(basename "${url%%\?*}")
    if [ -n "$repo" ] && [ -n "$file" ]; then
      if huggingface-cli download "$repo" "$file" \
           --local-dir "$COMFY_DIR/$dir" >/dev/null 2>&1; then
        if [ -f "$COMFY_DIR/$dir/$file" ] && [ "$file" != "$filename" ]; then
          mv -f "$COMFY_DIR/$dir/$file" "$dest" 2>/dev/null || true
        fi
        if [ -f "$dest" ]; then
          ok "$label (hf-cli)"
          return 0
        fi
      fi
    fi
  fi

  # 2) aria2c
  if aria2c -c -x 16 -s 16 -k 1M --console-log-level=error \
    --max-tries=8 --retry-wait=4 --timeout=120 --connect-timeout=30 \
    "$url" -d "$COMFY_DIR/$dir" -o "$filename" 2>/dev/null; then
    ok "$label"
    return 0
  fi

  # 3) Mirror
  local mirror_url="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
  if aria2c -c -x 16 -s 16 -k 1M --console-log-level=error \
    "$mirror_url" -d "$COMFY_DIR/$dir" -o "$filename" 2>/dev/null; then
    ok "$label (mirror)"
    return 0
  fi

  info "⚠️  $label indirilemedi (opsiyonel)"
  return 1
}

# ── 7. MODEL İNDİRMELERİ ──────────────────────────────────────────
step "ADIM 6/9: Model Paketleri İndiriliyor"

# === Ana Turbo FP8 (Comfy-Org resmi) ===
download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors" \
  "models/diffusion_models" "krea2_turbo_fp8_scaled.safetensors" \
  "Krea 2 Turbo FP8 Scaled"

# === Text Encoder ===
download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors" \
  "models/text_encoders" "qwen3vl_4b_fp8_scaled.safetensors" \
  "Qwen3-VL 4B FP8 Text Encoder"

# === VAE ===
download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors" \
  "models/vae" "qwen_image_vae.safetensors" \
  "Qwen Image VAE"

# === SeedVR2 + Upscaler ===
download \
  "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
  "models/diffusion_models" "seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
  "SeedVR2 3B FP8" || true

download \
  "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth" \
  "models/upscale_models" "4x-UltraSharp.pth" \
  "4x-UltraSharp" || true

# === Style LoRA'lar (resmi Comfy-Org) ===
download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_softwatercolor.safetensors" \
  "models/loras" "krea2_softwatercolor.safetensors" \
  "Soft Watercolor LoRA" || true

download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_retroanime.safetensors" \
  "models/loras" "krea2_retroanime.safetensors" \
  "Retro Anime LoRA" || true

download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_vintagetarot.safetensors" \
  "models/loras" "krea2_vintagetarot.safetensors" \
  "Vintage Tarot LoRA" || true

download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_darkbrush.safetensors" \
  "models/loras" "krea2_darkbrush.safetensors" \
  "Dark Brush LoRA" || true

download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_neondrip.safetensors" \
  "models/loras" "krea2_neondrip.safetensors" \
  "Neon Drip LoRA" || true

download \
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_sunsetblur.safetensors" \
  "models/loras" "krea2_sunsetblur.safetensors" \
  "Sunset Blur LoRA" || true

# ── 8. DOĞRULAMA ──────────────────────────────────────────────────
step "ADIM 7/9: Kurulum Doğrulaması"
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

verify "models/diffusion_models/krea2_turbo_fp8_scaled.safetensors" "Krea 2 Turbo FP8"
verify "models/text_encoders/qwen3vl_4b_fp8_scaled.safetensors"     "Qwen3-VL 4B TE"
verify "models/vae/qwen_image_vae.safetensors"                      "Qwen Image VAE"

if [ $ERRORS -eq 0 ]; then
  ok "TÜM KRİTİK MODELLER DOĞRULANDI"
else
  fail "$ERRORS adet kritik model eksik!"
fi

# ── 9. BAŞLAT ─────────────────────────────────────────────────────
step "ADIM 8/9: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
  "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ KREA 2 TURBO FP8 RICH KURULUM TAMAMLANDI                 ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Tag     : $COMFY_TAG                                       ║${NC}"
echo -e "${GREEN}║  Log     : tmux attach -t comfyui                            ║${NC}"
echo -e "${GREEN}║  Durdur  : tmux kill-session -t comfyui                      ║${NC}"
echo -e "${GREEN}║  Port    : 8188                                              ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Ana model : krea2_turbo_fp8_scaled.safetensors (8-step)     ║${NC}"
echo -e "${GREEN}║  TE        : qwen3vl_4b_fp8_scaled.safetensors               ║${NC}"
echo -e "${GREEN}║  VAE       : qwen_image_vae.safetensors                      ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Önerilen ayarlar:                                           ║${NC}"
echo -e "${GREEN}║    Steps  : 8                                                ║${NC}"
echo -e "${GREEN}║    CFG    : 1.0 (veya 0)                                     ║${NC}"
echo -e "${GREEN}║    Sampler: euler / er_sde                                   ║${NC}"
echo -e "${GREEN}║    Scheduler: simple                                         ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  CLIPLoader type → krea2  (önemli!)                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Template araması: ComfyUI içinde \"Krea-2\" veya \"Krea 2\" yaz${NC}"
echo -e "${CYAN}Hafta içi hızlı → setup_full.sh (Flux.1)${NC}"
echo -e "${CYAN}Klein denemek  → setup_klein.sh${NC}"
echo -e "${CYAN}Krea 2 Turbo   → setup_krea2.sh (bu script)${NC}"
echo ""
