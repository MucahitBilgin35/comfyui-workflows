#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX.1 DEV FP8 — OPTIMIZED STABLE SETUP             ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── AYARLAR ───────────────────────────────────────────────────────
COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.33.1"
TORCH_INDEX="https://download.pytorch.org/whl/cu126" # veya cu130 / cu124

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${YELLOW}══════════════════════════════════════════════════${NC}"; echo -e "${YELLOW} $1${NC}"; echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
fail()  { echo -e "  ${RED}❌ $1${NC}"; }
info()  { echo -e "  ${CYAN}→ $1${NC}"; }

# ── 0. DISK VE SİSTEM KİLİTLERİ ──────────────────────────────────
step "ADIM 0/7: Sistem Hazırlığı ve Disk Kontrolü"
mkdir -p /workspace

# Olası kilitleri ve IPv6 takılmalarını temizle
killall apt apt-get dpkg unattended-upgrade 2>/dev/null || true
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
echo 'Acquire::http::Timeout "15";' >> /etc/apt/apt.conf.d/99force-ipv4
echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99force-ipv4

AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 45 ]; then
    fail "Sadece ${AVAIL}GB boş alan var. Minimum 45GB önerilir!"
    exit 1
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 1. SİSTEM PAKETLERİ ───────────────────────────────────────────
step "ADIM 1/7: Sistem Paketleri Kuruluyor"
# Sorun çıkaran nvidia listesini geçici olarak devre dışı bırak/hızlı güncelle
apt-get update -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
    python3-venv python3-pip curl wget ca-certificates
ok "Sistem paketleri kuruldu"

# ── 2. COMFYUI ────────────────────────────────────────────────────
step "ADIM 2/7: ComfyUI Kurulumu (tag: $COMFY_TAG)"

if [ -d "$COMFY_DIR" ] && [ -d "$COMFY_DIR/.git" ]; then
    cd "$COMFY_DIR"
    git checkout "$COMFY_TAG" 2>/dev/null || true
    ok "ComfyUI dizini hazır"
else
    rm -rf "$COMFY_DIR"
    git clone --depth=1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
    ok "ComfyUI $COMFY_TAG kuruldu"
fi

cd "$COMFY_DIR"

if [ ! -d "venv" ]; then
    python3 -m venv venv
    ok "Virtualenv oluşturuldu"
fi
source venv/bin/activate
pip install --upgrade pip wheel setuptools

info "PyTorch kuruluyor (İndirme durumunu takip edebilirsiniz)..."
pip install torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -r requirements.txt
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
    ["ComfyUI-Pixaroma"]="https://github.com/pixaroma/ComfyUI-Pixaroma.git"
)

for name in "${!NODES[@]}"; do
    if [ -d "$name" ]; then
        ok "$name zaten var"
    else
        info "$name klonlanıyor..."
        git clone --depth=1 "${NODES[$name]}" "$name" 2>/dev/null || fail "$name klonlanamadı"
    fi
done

for req in */requirements.txt; do
    [ -f "$req" ] || continue
    info "Bağımlılık yükleniyor: $req"
    pip install -r "$req" 2>/dev/null || true
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
    if aria2c -c -x 16 -s 16 -k 1M --file-allocation=none \
        --max-tries=5 --retry-wait=2 --timeout=30 --connect-timeout=15 \
        --summary-interval=10 \
        "$URL" -d "$DIR" -o "$FILE"; then
        ok "$DESC indirildi"
        return 0
    else
        fail "$DESC İNDİRİLEMEDİ!"
        return 1
    fi
}

download "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors" "models/diffusion_models" "flux1-dev-fp8.safetensors" "Flux.1 Dev FP8 (~11.9 GB)"
download "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" "models/text_encoders" "clip_l.safetensors" "CLIP-L"
download "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" "models/text_encoders" "t5xxl_fp8_e4m3fn.safetensors" "T5-XXL FP8"
download "https://huggingface.co/camenduru/FLUX.1-dev/resolve/main/ae.safetensors" "models/vae" "ae.safetensors" "Flux VAE"
download "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro/resolve/main/diffusion_pytorch_model.safetensors" "models/controlnet" "flux-dev-controlnet-union-pro.safetensors" "ControlNet Union Pro"

# LoRA'lar
download "https://huggingface.co/XLabs-AI/flux-lora-collection/resolve/main/realism_lora_comfy_converted.safetensors" "models/loras" "flux_realism.safetensors" "Realism LoRA"
download "https://huggingface.co/XLabs-AI/flux-lora-collection/resolve/main/anime_lora_comfy_converted.safetensors" "models/loras" "flux_anime.safetensors" "Anime LoRA"
download "https://huggingface.co/XLabs-AI/flux-lora-collection/resolve/main/art_lora_comfy_converted.safetensors" "models/loras" "flux_art.safetensors" "Art LoRA"
download "https://huggingface.co/XLabs-AI/flux-lora-collection/resolve/main/mjv6_lora_comfy_converted.safetensors" "models/loras" "flux_mjv6.safetensors" "Midjourney v6 LoRA"
download "https://huggingface.co/XLabs-AI/flux-lora-collection/resolve/main/scenery_lora_comfy_converted.safetensors" "models/loras" "flux_scenery.safetensors" "Scenery LoRA"
download "https://huggingface.co/Shakker-Labs/FLUX.1-dev-LoRA-add-details/resolve/main/FLUX-dev-lora-add_details.safetensors" "models/loras" "flux_add_details.safetensors" "Add Details LoRA"
download "https://huggingface.co/alimama-creative/FLUX.1-Turbo-Alpha/resolve/main/diffusion_pytorch_model.safetensors" "models/loras" "flux_turbo_alpha.safetensors" "Flux Turbo Alpha"
download "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors" "models/loras" "flux_realism_for_xlabs_node.safetensors" "Realism LoRA (XLabs)"

# Upscale & IP-Adapter
download "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" "models/upscale_models" "4x-UltraSharp.pth" "4x-UltraSharp"
download "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" "models/clip_vision" "sigclip_vision_patch14_384.safetensors" "SigCLIP Vision"
download "https://huggingface.co/XLabs-AI/flux-ip-adapter/resolve/main/ip_adapter.safetensors" "models/xlabs/ipadapters" "ip_adapter.safetensors" "XLabs IP-Adapter"
download "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors" "models/clip_vision" "clip-vit-large-patch14.safetensors" "CLIP ViT-L/14"

# ── 6. UYUMLULUK SYMLINK'LERİ ─────────────────────────────────────
step "ADIM 6/7: Uyumluluk Symlink'leri"
ln -sf "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" "$COMFY_DIR/models/unet/flux1-dev-fp8.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/clip_l.safetensors" "$COMFY_DIR/models/clip/clip_l.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" "$COMFY_DIR/models/clip/t5xxl_fp8_e4m3fn.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/xlabs/ipadapters/ip_adapter.safetensors" "$COMFY_DIR/models/ipadapter/ip_adapter.safetensors" 2>/dev/null || true
ok "Symlink'ler oluşturuldu"

# ── 7. BAŞLAT ─────────────────────────────────────────────────────
step "ADIM 7/7: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true

tmux new-session -d -s comfyui \
    "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ KURULUM BAŞARIYLA TAMAMLANDI VE COMFYUI BAŞLATILDI       ║${NC}"
echo -e "${GREEN}║  Port: 8188                                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
