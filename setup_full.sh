#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX.1 DEV FP8 — STABLE SETUP (setup_full.sh)       ║
# ║  Son Güncelleme : 18 Ağustos 2026                               ║
# ║  Hedef          : 2-3 ay boyunca tutarlı kurulum                ║
# ║  Tested for     : Clore.ai / RTX 3090-4090 / 64GB+ RAM          ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── AYARLAR ───────────────────────────────────────────────────────
COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.33.1"                          # pinlenmiş stabil sürüm
TORCH_INDEX="https://download.pytorch.org/whl/cu130"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"  # yavaş bölgeler için
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

# ── 0. DISK KONTROLÜ ──────────────────────────────────────────────
step "ADIM 0/7: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 45 ]; then
    fail "Sadece ${AVAIL}GB boş alan var. Minimum 45GB önerilir!"
    exit 1
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 1. SİSTEM PAKETLERİ ───────────────────────────────────────────
step "ADIM 1/7: Sistem Paketleri"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
    python3-venv python3-pip curl wget ca-certificates > /dev/null 2>&1 || true
ok "Sistem paketleri kuruldu"

# ── 2. COMFYUI (PINLENMİŞ) ────────────────────────────────────────
step "ADIM 2/7: ComfyUI Kurulumu (tag: $COMFY_TAG)"

if [ -d "$COMFY_DIR" ] && [ -d "$COMFY_DIR/.git" ]; then
    cd "$COMFY_DIR"
    git fetch --tags --quiet || true
    CURRENT=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
    if [ "$CURRENT" = "$COMFY_TAG" ]; then
        ok "ComfyUI zaten $COMFY_TAG sürümünde"
    else
        info "Mevcut sürüm: $CURRENT → $COMFY_TAG'e geçiliyor"
        git checkout "$COMFY_TAG" 2>/dev/null || {
            git fetch --depth=1 origin tag "$COMFY_TAG"
            git checkout "$COMFY_TAG"
        }
        ok "ComfyUI $COMFY_TAG'e güncellendi"
    fi
else
    rm -rf "$COMFY_DIR"
    git clone --depth=1 --branch "$COMFY_TAG" \
        https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
    ok "ComfyUI $COMFY_TAG sıfırdan kuruldu"
fi

cd "$COMFY_DIR"

# Virtualenv
if [ ! -d "venv" ]; then
    python3 -m venv venv
    ok "Virtualenv oluşturuldu"
fi
source venv/bin/activate
pip install --upgrade pip wheel setuptools -q

# Torch (cu130)
info "PyTorch (cu130) kuruluyor..."
pip install --quiet torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install --quiet -r requirements.txt
ok "ComfyUI bağımlılıkları kuruldu"

# ── 3. CUSTOM NODE'LAR ────────────────────────────────────────────
step "ADIM 3/7: Custom Node'lar"

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
)

for name in "${!NODES[@]}"; do
    if [ -d "$name" ]; then
        ok "$name zaten var"
    else
        info "$name klonlanıyor..."
        if git clone --depth=1 "${NODES[$name]}" "$name" 2>/dev/null; then
            ok "$name kuruldu"
        else
            fail "$name klonlanamadı (devam ediliyor)"
        fi
    fi
done

# requirements
for req in */requirements.txt; do
    [ -f "$req" ] || continue
    info "Bağımlılık: $req"
    pip install --quiet -r "$req" 2>/dev/null || true
done
ok "Custom node'lar hazır"

cd "$COMFY_DIR"

# ── 4. MODEL KLASÖRLERİ ───────────────────────────────────────────
step "ADIM 4/7: Model Klasörleri"
mkdir -p models/{diffusion_models,unet,text_encoders,clip,vae,loras,controlnet,upscale_models,clip_vision,ipadapter,xlabs/ipadapters}
ok "Klasörler oluşturuldu"

# ── 5. MODEL İNDİRME ──────────────────────────────────────────────
step "ADIM 5/7: Model İndirme"

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
    # Önce mirror dene, sonra orijinal
    local MIRROR_URL="${URL/https:\/\/huggingface.co/https:\/\/hf-mirror.com}"
    
    if aria2c -c -x 16 -s 16 -k 1M \
        --max-tries=8 --retry-wait=4 --timeout=60 --connect-timeout=20 \
        --console-log-level=error \
        "$MIRROR_URL" -d "$DIR" -o "$FILE" 2>/dev/null; then
        ok "$DESC"
        return 0
    fi

    # Fallback: orijinal HF
    info "Mirror başarısız, orijinal kaynaktan deneniyor..."
    if aria2c -c -x 16 -s 16 -k 1M \
        --max-tries=8 --retry-wait=4 --timeout=60 --connect-timeout=20 \
        --console-log-level=error \
        "$URL" -d "$DIR" -o "$FILE"; then
        ok "$DESC"
        return 0
    else
        fail "$DESC İNDİRİLEMEDİ!"
        return 1
    fi
}

# A. Flux.1 Dev FP8 (Kijai)
download \
    "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors" \
    "models/diffusion_models" "flux1-dev-fp8.safetensors" \
    "Flux.1 Dev FP8 (~11.9 GB)"

# B. Text Encoders
download \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
    "models/text_encoders" "clip_l.safetensors" \
    "CLIP-L"

download \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
    "models/text_encoders" "t5xxl_fp8_e4m3fn.safetensors" \
    "T5-XXL FP8"

# C. VAE (public mirror)
download \
    "https://huggingface.co/camenduru/FLUX.1-dev/resolve/main/ae.safetensors" \
    "models/vae" "ae.safetensors" \
    "Flux VAE"

# D. ControlNet Union Pro
download \
    "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro/resolve/main/diffusion_pytorch_model.safetensors" \
    "models/controlnet" "flux-dev-controlnet-union-pro.safetensors" \
    "ControlNet Union Pro"

# E. Realism LoRA
download \
    "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors" \
    "models/loras" "flux_realism.safetensors" \
    "Realism LoRA"

# F. 4x-UltraSharp
download \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" \
    "models/upscale_models" "4x-UltraSharp.pth" \
    "4x-UltraSharp"

# G. CLIP Vision (IP-Adapter)
download \
    "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
    "models/clip_vision" "sigclip_vision_patch14_384.safetensors" \
    "SigCLIP Vision"

# H. IP-Adapter
download \
    "https://huggingface.co/XLabs-AI/flux-ip-adapter/resolve/main/ip_adapter.safetensors" \
    "models/xlabs/ipadapters" "ip_adapter.safetensors" \
    "XLabs IP-Adapter"

# ── 6. UYUMLULUK SYMLINK'LERİ ─────────────────────────────────────
step "ADIM 6/7: Uyumluluk Symlink'leri"

# diffusion_models ↔ unet
ln -sf "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" \
       "$COMFY_DIR/models/unet/flux1-dev-fp8.safetensors" 2>/dev/null || true

# text_encoders ↔ clip
ln -sf "$COMFY_DIR/models/text_encoders/clip_l.safetensors" \
       "$COMFY_DIR/models/clip/clip_l.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" \
       "$COMFY_DIR/models/clip/t5xxl_fp8_e4m3fn.safetensors" 2>/dev/null || true

# IP-Adapter her iki yere de
ln -sf "$COMFY_DIR/models/xlabs/ipadapters/ip_adapter.safetensors" \
       "$COMFY_DIR/models/ipadapter/ip_adapter.safetensors" 2>/dev/null || true

ok "Symlink'ler oluşturuldu"

# ── 7. DOĞRULAMA ──────────────────────────────────────────────────
step "ADIM 7/7: Doğrulama"
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

verify "models/diffusion_models/flux1-dev-fp8.safetensors" "Flux Dev FP8"
verify "models/text_encoders/clip_l.safetensors"             "CLIP-L"
verify "models/text_encoders/t5xxl_fp8_e4m3fn.safetensors"  "T5-XXL FP8"
verify "models/vae/ae.safetensors"                         "VAE"
verify "models/controlnet/flux-dev-controlnet-union-pro.safetensors" "ControlNet Union Pro"
verify "models/loras/flux_realism.safetensors"              "Realism LoRA"
verify "models/upscale_models/4x-UltraSharp.pth"            "4x-UltraSharp"
verify "models/clip_vision/sigclip_vision_patch14_384.safetensors" "SigCLIP Vision"
verify "models/xlabs/ipadapters/ip_adapter.safetensors"     "IP-Adapter"

echo ""
if [ $ERRORS -eq 0 ]; then
    ok "TÜM KRİTİK MODELLER DOĞRULANDI — SIFIR HATA!"
else
    fail "$ERRORS adet model eksik! Kurulumu kontrol et."
fi

# ── BAŞLAT ────────────────────────────────────────────────────────
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true

# venv içinden başlat
tmux new-session -d -s comfyui \
    "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ KURULUM TAMAMLANDI                                       ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  ComfyUI Tag : $COMFY_TAG                                   ║${NC}"
echo -e "${GREEN}║  Log         : tmux attach -t comfyui                        ║${NC}"
echo -e "${GREEN}║  Çıkış       : Ctrl+B sonra D                                ║${NC}"
echo -e "${GREEN}║  Durdur      : tmux kill-session -t comfyui                  ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Port        : 8188                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Not: Yavaş bölgelerde daha hızlı indirme için script çalıştırmadan önce:${NC}"
echo -e "${CYAN}  export HF_ENDPOINT=https://hf-mirror.com${NC}"
echo ""
