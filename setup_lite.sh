#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX DEV — HAFİF PAKET (setup_lite.sh)              ║
# ║  Sıfır Token — Sadece Temel Görsel Üretim                      ║
# ║  Son Güncelleme: Ağustos 2026                                   ║
# ║                                                                  ║
# ║  İçerik: Flux Dev FP8 + CLIP + T5 + VAE + Manager              ║
# ║  Toplam İndirme: ~17.5 GB                                       ║
# ║  Minimum Disk: 25 GB                                             ║
# ║                                                                  ║
# ║  Kullanım:                                                      ║
# ║  curl -sSL https://raw.githubusercontent.com/MucahitBilgin35/   ║
# ║  comfyui-workflows/main/setup_lite.sh | bash                    ║
# ╚══════════════════════════════════════════════════════════════════╝
set -e

COMFY_DIR="/workspace/ComfyUI"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo -e "\n${YELLOW}══════════════════════════════════════════════════${NC}"; echo -e "${YELLOW}  $1${NC}"; echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"; }
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }

# ── Disk Kontrolü ──
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 25 ]; then
    fail "Sadece ${AVAIL}GB boş alan var. Lite paket için minimum 25GB gerekli!"
    exit 1
fi

# ── Sistem Paketleri ──
step "ADIM 1/4: Sistem Paketleri"
apt-get update -qq
apt-get install -y -qq git aria2 tmux ffmpeg libgl1 libglib2.0-0 > /dev/null 2>&1 || true
ok "Paketler kuruldu"

# ── ComfyUI ──
step "ADIM 2/4: ComfyUI"
if [ ! -d "$COMFY_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
    cd "$COMFY_DIR"
    pip install -q --break-system-packages -r requirements.txt 2>/dev/null || pip install -q -r requirements.txt
    ok "ComfyUI kuruldu"
else
    cd "$COMFY_DIR"
    ok "ComfyUI zaten mevcut"
fi

# ── Sadece Manager ──
mkdir -p "$COMFY_DIR/custom_nodes"
cd "$COMFY_DIR/custom_nodes"
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git 2>/dev/null || true
ok "ComfyUI-Manager kuruldu"

# ── Temel Modeller ──
step "ADIM 3/4: Temel Modeller"
cd "$COMFY_DIR"
mkdir -p models/{unet,diffusion_models,clip,text_encoders,vae}

download() {
    local URL=$1; local DIR=$2; local FILE=$3; local DESC=$4
    if [ -f "$DIR/$FILE" ]; then ok "$DESC (zaten var)"; else
        echo -e "  ⬇️  $DESC indiriliyor..."
        aria2c -c -x 16 -s 16 -k 1M "$URL" -d "$DIR" -o "$FILE" --console-log-level=error
        [ -f "$DIR/$FILE" ] && ok "$DESC" || fail "$DESC"
    fi
}

download "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors" \
    "models/unet" "flux1-dev-fp8.safetensors" "Flux Dev FP8 UNet (~11.9 GB)"

download "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
    "models/clip" "clip_l.safetensors" "CLIP-L (~246 MB)"

download "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
    "models/clip" "t5xxl_fp8_e4m3fn.safetensors" "T5-XXL FP8 (~4.89 GB)"

download "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" \
    "models/vae" "ae.safetensors" "Flux VAE (~335 MB)"

# ── Symlink'ler ──
ln -sf "$COMFY_DIR/models/unet/flux1-dev-fp8.safetensors" "$COMFY_DIR/models/diffusion_models/" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/clip/clip_l.safetensors" "$COMFY_DIR/models/text_encoders/" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/clip/t5xxl_fp8_e4m3fn.safetensors" "$COMFY_DIR/models/text_encoders/" 2>/dev/null || true

# ── Doğrulama ──
step "ADIM 4/4: Doğrulama"
ERRORS=0
verify() {
    local FILE=$1; local DESC=$2
    if [ -f "$COMFY_DIR/$FILE" ]; then SIZE=$(du -h "$COMFY_DIR/$FILE" | cut -f1); ok "$DESC ($SIZE)"; else fail "$DESC BULUNAMADI"; ERRORS=$((ERRORS+1)); fi
}
verify "models/unet/flux1-dev-fp8.safetensors" "Flux Dev FP8 UNet"
verify "models/clip/clip_l.safetensors" "CLIP-L Encoder"
verify "models/clip/t5xxl_fp8_e4m3fn.safetensors" "T5-XXL FP8 Encoder"
verify "models/vae/ae.safetensors" "Flux VAE"

echo ""
[ $ERRORS -eq 0 ] && ok "TEMEL MODELLER TAMAM!" || fail "$ERRORS model eksik!"

# ── ComfyUI Başlat ──
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui "cd $COMFY_DIR && python main.py --listen 0.0.0.0 --port 8188 --fast"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ LİTE KURULUM TAMAMLANDI!                           ║${NC}"
echo -e "${GREEN}║  Loglar:  tmux attach -t comfyui                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
