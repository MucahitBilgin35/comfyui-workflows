#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX.1 DEV — WEEKEND RICH SETUP (setup_weekend.sh)  ║
# ║  Son Güncelleme : 19 Ağustos 2026                               ║
# ║  Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM               ║
# ║  İçerik         : Full + T5 FP16 + Redux + Depth/Canny/HED      ║
# ║                   + SeedVR2 3B FP8 + face tools                 ║
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
fail()  { echo -e "  ${RED}❌ $1${NC}"; }
info()  { echo -e "  ${CYAN}→ $1${NC}"; }

# ── 0. DISK ───────────────────────────────────────────────────────
step "ADIM 0/9: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 70 ]; then
    fail "Sadece ${AVAIL}GB boş. Zengin weekend paketi için minimum 70GB önerilir!"
    exit 1
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
step "ADIM 2/9: ComfyUI ($COMFY_TAG)"

if [ -d "$COMFY_DIR" ] && [ -d "$COMFY_DIR/.git" ]; then
    cd "$COMFY_DIR"
    git fetch --tags --quiet || true
    CURRENT=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
    if [ "$CURRENT" = "$COMFY_TAG" ]; then
        ok "ComfyUI zaten $COMFY_TAG"
    else
        info "Mevcut: $CURRENT → $COMFY_TAG"
        git checkout "$COMFY_TAG" 2>/dev/null || {
            git fetch --depth=1 origin tag "$COMFY_TAG"
            git checkout "$COMFY_TAG"
        }
        ok "ComfyUI $COMFY_TAG"
    fi
else
    rm -rf "$COMFY_DIR"
    git clone --depth=1 --branch "$COMFY_TAG" \
        https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
    ok "ComfyUI $COMFY_TAG sıfırdan kuruldu"
fi

cd "$COMFY_DIR"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    ok "Virtualenv oluşturuldu"
fi
source venv/bin/activate
pip install --upgrade pip wheel setuptools -q
info "PyTorch cu130..."
pip install --quiet torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install --quiet -r requirements.txt
ok "Bağımlılıklar kuruldu"

# ── 3. CUSTOM NODE'LAR ────────────────────────────────────────────
step "ADIM 3/9: Custom Node'lar"
mkdir -p custom_nodes
cd custom_nodes

declare -A NODES=(
    ["ComfyUI-Manager"]="https://github.com/ltdrdata/ComfyUI-Manager.git"
    ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
    ["ComfyUI-Custom-Scripts"]="https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    ["comfyui_controlnet_aux"]="https://github.com/Fannovel16/comfyui_controlnet_aux.git"
    ["ComfyUI-Impact-Pack"]="https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
    ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
    ["ComfyUI_IPAdapter_plus"]="https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
    ["x-flux-comfyui"]="https://github.com/XLabs-AI/x-flux-comfyui.git"
    ["was-node-suite-comfyui"]="https://github.com/WASasquatch/was-node-suite-comfyui.git"
)

for name in "${!NODES[@]}"; do
    if [ -d "$name" ]; then
        ok "$name mevcut"
    else
        info "$name..."
        if git clone --depth=1 "${NODES[$name]}" "$name" 2>/dev/null; then
            ok "$name"
        else
            fail "$name klonlanamadı (devam)"
        fi
    fi
done

for req in */requirements.txt; do
    [ -f "$req" ] || continue
    pip install --quiet -r "$req" 2>/dev/null || true
done
ok "Custom node'lar hazır"
cd "$COMFY_DIR"

# ── 4. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 4/9: Klasörler"
mkdir -p models/{diffusion_models,unet,text_encoders,clip,vae,loras,controlnet,upscale_models,clip_vision,ipadapter,xlabs/ipadapters,style_models,ultralytics/bbox,ultralytics/segm}
ok "Klasörler hazır"

# ── 5. İNDİRME FONKSİYONU ─────────────────────────────────────────
download() {
    local URL="$1"
    local DIR="$2"
    local FILE="$3"
    local DESC="$4"
    local TARGET="$DIR/$FILE"

    if [ -f "$TARGET" ]; then
        local SIZE
        SIZE=$(du -h "$TARGET" | cut -f1)
        ok "$DESC ($SIZE) — zaten var"
        return 0
    fi

    info "$DESC indiriliyor..."
    local MIRROR_URL="${URL/https:\/\/huggingface.co/https:\/\/hf-mirror.com}"

    if aria2c -c -x 16 -s 16 -k 1M \
        --max-tries=8 --retry-wait=4 --timeout=90 --connect-timeout=25 \
        --console-log-level=error \
        "$MIRROR_URL" -d "$DIR" -o "$FILE" 2>/dev/null; then
        ok "$DESC"
        return 0
    fi

    info "Mirror başarısız → orijinal..."
    if aria2c -c -x 16 -s 16 -k 1M \
        --max-tries=8 --retry-wait=4 --timeout=90 --connect-timeout=25 \
        --console-log-level=error \
        "$URL" -d "$DIR" -o "$FILE"; then
        ok "$DESC"
        return 0
    else
        fail "$DESC İNDİRİLEMEDİ"
        return 1
    fi
}

# ── 6. TEMEL MODELLER (FULL) ──────────────────────────────────────
step "ADIM 5/9: Temel Modeller (Full paket)"

download \
    "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors" \
    "models/diffusion_models" "flux1-dev-fp8.safetensors" \
    "Flux.1 Dev FP8 (~11.9 GB)"

download \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
    "models/text_encoders" "clip_l.safetensors" \
    "CLIP-L"

download \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
    "models/text_encoders" "t5xxl_fp8_e4m3fn.safetensors" \
    "T5-XXL FP8"

download \
    "https://huggingface.co/camenduru/FLUX.1-dev/resolve/main/ae.safetensors" \
    "models/vae" "ae.safetensors" \
    "Flux VAE"

download \
    "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro/resolve/main/diffusion_pytorch_model.safetensors" \
    "models/controlnet" "flux-dev-controlnet-union-pro.safetensors" \
    "ControlNet Union Pro"

download \
    "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors" \
    "models/loras" "flux_realism.safetensors" \
    "Realism LoRA"

download \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" \
    "models/upscale_models" "4x-UltraSharp.pth" \
    "4x-UltraSharp"

download \
    "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
    "models/clip_vision" "sigclip_vision_patch14_384.safetensors" \
    "SigCLIP Vision"

download \
    "https://huggingface.co/XLabs-AI/flux-ip-adapter/resolve/main/ip_adapter.safetensors" \
    "models/xlabs/ipadapters" "ip_adapter.safetensors" \
    "XLabs IP-Adapter"

# ── 7. ZENGİN WEEKEND EKSTRALARI ──────────────────────────────────
step "ADIM 6/9: Zengin Weekend Ekstraları (~+18–22 GB)"

# T5 FP16 — 64 GB RAM için kalite encoder
download \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
    "models/text_encoders" "t5xxl_fp16.safetensors" \
    "T5-XXL FP16 (~9.8 GB)"

# Redux — görsel stil / varyasyon
download \
    "https://huggingface.co/Comfy-Org/Flux1-Redux-Dev/resolve/main/flux1-redux-dev.safetensors" \
    "models/style_models" "flux1-redux-dev.safetensors" \
    "Flux Redux (~130 MB)"

# XLabs spesifik ControlNet'ler
download \
    "https://huggingface.co/XLabs-AI/flux-controlnet-depth-v3/resolve/main/flux-depth-controlnet-v3.safetensors" \
    "models/controlnet" "flux-depth-controlnet-v3.safetensors" \
    "XLabs Depth ControlNet (~1.5 GB)"

download \
    "https://huggingface.co/XLabs-AI/flux-controlnet-canny-v3/resolve/main/flux-canny-controlnet-v3.safetensors" \
    "models/controlnet" "flux-canny-controlnet-v3.safetensors" \
    "XLabs Canny ControlNet (~1.5 GB)"

download \
    "https://huggingface.co/XLabs-AI/flux-controlnet-hed-v3/resolve/main/flux-hed-controlnet-v3.safetensors" \
    "models/controlnet" "flux-hed-controlnet-v3.safetensors" \
    "XLabs HED ControlNet (~1.5 GB)" \
    || info "HED atlandı (zorunlu değil)"

# SeedVR2 3B FP8 (numz — güncel çalışan yol)
download \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
    "models/diffusion_models" "seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
    "SeedVR2 3B FP8 (upscale)" \
    || info "SeedVR2 model atlandı (zorunlu değil)"

download \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors" \
    "models/vae" "seedvr2_ema_vae_fp16.safetensors" \
    "SeedVR2 EMA VAE" \
    || info "SeedVR2 VAE atlandı (zorunlu değil)"

# Alternatif klasik upscaler
download \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth" \
    "models/upscale_models" "4x_NMKD-Siax_200k.pth" \
    "4x NMKD-Siax" \
    || true

# Face detectors (Impact-Pack)
download \
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt" \
    "models/ultralytics/bbox" "face_yolov8m.pt" \
    "Face YOLO v8m" \
    || true

download \
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n.pt" \
    "models/ultralytics/bbox" "face_yolov8n.pt" \
    "Face YOLO v8n" \
    || true

ok "Weekend ekstraları tamamlandı"

# ── 8. SYMLINK'LER ────────────────────────────────────────────────
step "ADIM 7/9: Symlink'ler"

ln -sf "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" \
       "$COMFY_DIR/models/unet/flux1-dev-fp8.safetensors" 2>/dev/null || true

ln -sf "$COMFY_DIR/models/text_encoders/clip_l.safetensors" \
       "$COMFY_DIR/models/clip/clip_l.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" \
       "$COMFY_DIR/models/clip/t5xxl_fp8_e4m3fn.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/t5xxl_fp16.safetensors" \
       "$COMFY_DIR/models/clip/t5xxl_fp16.safetensors" 2>/dev/null || true

# IP-Adapter her iki yere
ln -sf "$COMFY_DIR/models/xlabs/ipadapters/ip_adapter.safetensors" \
       "$COMFY_DIR/models/ipadapter/ip_adapter.safetensors" 2>/dev/null || true

ok "Symlink'ler tamam (IP-Adapter dahil)"

# ── 9. DOĞRULAMA ──────────────────────────────────────────────────
step "ADIM 8/9: Doğrulama"
ERRORS=0

verify() {
    local FILE="$1"
    local DESC="$2"
    if [ -f "$COMFY_DIR/$FILE" ]; then
        local SIZE
        SIZE=$(du -h "$COMFY_DIR/$FILE" | cut -f1)
        ok "$DESC ($SIZE)"
    else
        fail "$DESC eksik → $FILE"
        ERRORS=$((ERRORS + 1))
    fi
}

verify "models/diffusion_models/flux1-dev-fp8.safetensors"              "Flux Dev FP8"
verify "models/text_encoders/clip_l.safetensors"                        "CLIP-L"
verify "models/text_encoders/t5xxl_fp8_e4m3fn.safetensors"              "T5 FP8"
verify "models/text_encoders/t5xxl_fp16.safetensors"                    "T5 FP16"
verify "models/vae/ae.safetensors"                                      "VAE"
verify "models/controlnet/flux-dev-controlnet-union-pro.safetensors"    "ControlNet Union"
verify "models/controlnet/flux-depth-controlnet-v3.safetensors"         "Depth CN"
verify "models/controlnet/flux-canny-controlnet-v3.safetensors"         "Canny CN"
verify "models/style_models/flux1-redux-dev.safetensors"                "Redux"
verify "models/loras/flux_realism.safetensors"                          "Realism LoRA"
verify "models/clip_vision/sigclip_vision_patch14_384.safetensors"      "SigCLIP"
verify "models/xlabs/ipadapters/ip_adapter.safetensors"                 "IP-Adapter"
verify "models/ipadapter/ip_adapter.safetensors"                        "IP-Adapter symlink"
verify "models/diffusion_models/seedvr2_ema_3b_fp8_e4m3fn.safetensors"  "SeedVR2 3B FP8"

echo ""
if [ $ERRORS -eq 0 ]; then
    ok "KRİTİK MODELLER TAMAM"
else
    fail "$ERRORS kritik eksik — log'a bak"
fi

# ── BAŞLAT ────────────────────────────────────────────────────────
step "ADIM 9/9: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
    "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ WEEKEND RICH KURULUM TAMAMLANDI                          ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Tag     : $COMFY_TAG                                       ║${NC}"
echo -e "${GREEN}║  Log     : tmux attach -t comfyui                            ║${NC}"
echo -e "${GREEN}║  Durdur  : tmux kill-session -t comfyui                      ║${NC}"
echo -e "${GREEN}║  Port    : 8188                                              ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Ekstra  : T5 FP16 · Redux · Depth/Canny/HED · SeedVR2 3B    ║${NC}"
echo -e "${GREEN}║  Not     : DualCLIPLoader'da T5 = t5xxl_fp16 seçebilirsin     ║${NC}"
echo -e "${GREEN}║  SeedVR2 : Gerekirse Manager'dan SeedVR2 node kur            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Hafta içi hızlı → setup_full.sh${NC}"
echo -e "${CYAN}Hafta sonu zengin → setup_weekend.sh (bu script)${NC}"
echo ""
