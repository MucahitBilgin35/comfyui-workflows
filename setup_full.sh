#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║ COMFYUI + FLUX DEV — TAM PAKET KURULUM (setup_full.sh)          ║
# ║ Güncelleme: Ağustos 2026                                        ║
# ║ İçerik: Flux Dev FP8 + CLIP + T5 + VAE + Realism LoRA +         ║
# ║         ControlNet Union Pro + IP-Adapter + Upscale + 9 Node    ║
# ║                                                                  ║
# ║ Kullanım:                                                        ║
# ║ curl -sSL https://raw.githubusercontent.com/MucahitBilgin35/     ║
# ║ comfyui-workflows/main/setup_full.sh | bash                      ║
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

# ── ADIM 0: DISK KONTROLÜ ──────────────────────────────────────────
step "ADIM 0/6: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 40 ]; then
    fail "Sadece ${AVAIL}GB boş alan var. Minimum 40GB gerekli!"
    exit 1
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB mevcut"

# ── ADIM 1: SİSTEM PAKETLERİ ───────────────────────────────────────
step "ADIM 1/6: Sistem Paketleri"
apt-get update -qq
apt-get install -y -qq git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 > /dev/null 2>&1 || true
ok "Sistem paketleri kuruldu"

# ── ADIM 2: COMFYUI ────────────────────────────────────────────────
step "ADIM 2/6: ComfyUI Kurulumu"
if [ ! -d "$COMFY_DIR" ]; then
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
    cd "$COMFY_DIR"
    pip install -q --break-system-packages -r requirements.txt 2>/dev/null || pip install -q -r requirements.txt
    ok "ComfyUI sıfırdan kuruldu"
else
    cd "$COMFY_DIR"
    ok "ComfyUI zaten mevcut"
fi

# ── ADIM 3: CUSTOM NODE'LAR ────────────────────────────────────────
step "ADIM 3/6: Custom Node'lar (9 Adet — Paralel)"
mkdir -p "$COMFY_DIR/custom_nodes"
cd "$COMFY_DIR/custom_nodes"

git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git 2>/dev/null || true &
git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git 2>/dev/null || true &
git clone --depth=1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git 2>/dev/null || true &
git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git 2>/dev/null || true &
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git 2>/dev/null || true &
git clone --depth=1 https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git 2>/dev/null || true &
git clone --depth=1 https://github.com/cubiq/ComfyUI_essentials.git 2>/dev/null || true &
git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git 2>/dev/null || true &
git clone --depth=1 https://github.com/XLabs-AI/x-flux-comfyui.git 2>/dev/null || true &
wait

for req in */requirements.txt; do
    [ -f "$req" ] && (pip install -q --break-system-packages -r "$req" 2>/dev/null || pip install -q -r "$req" 2>/dev/null || true)
done
ok "Custom node'lar ve bağımlılıklar hazır"

# ── ADIM 4: MODEL İNDİRME ──────────────────────────────────────────
step "ADIM 4/6: Model İndirme"
cd "$COMFY_DIR"
mkdir -p models/{unet,diffusion_models,clip,text_encoders,vae,loras,controlnet,upscale_models,clip_vision,ipadapter,xlabs/ipadapters}

download() {
    local URL="$1"
    local DIR="$2"
    local FILE="$3"
    local DESC="$4"

    if [ -f "$DIR/$FILE" ]; then
        ok "$DESC (zaten var)"
        return 0
    fi

    echo -e "  ⬇️  $DESC indiriliyor..."
    # Daha dayanıklı aria2c ayarları (HF yavaş/kesintili olduğunda işe yarar)
    aria2c -c -x 16 -s 16 -k 1M \
           --max-tries=10 \
           --retry-wait=5 \
           --timeout=60 \
           --connect-timeout=30 \
           --console-log-level=error \
           "$URL" -d "$DIR" -o "$FILE"

    if [ -f "$DIR/$FILE" ]; then
        ok "$DESC"
    else
        fail "$DESC İNDİRİLEMEDİ!"
        return 1
    fi
}

# A. Flux Dev FP8 UNet (~11.9 GB)
download "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors" \
         "models/unet" "flux1-dev-fp8.safetensors" "Flux.1 Dev FP8 UNet"

# B. Text Encoders
download "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
         "models/clip" "clip_l.safetensors" "CLIP-L"

download "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
         "models/clip" "t5xxl_fp8_e4m3fn.safetensors" "T5-XXL FP8"

# C. VAE (resmi + token gerektirmez)
download "https://huggingface.co/camenduru/FLUX.1-dev/resolve/main/ae.safetensors" \
         "models/vae" "ae.safetensors" "Flux VAE"

# D. ControlNet Union Pro (güncel doğru kaynak)
download "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro/resolve/main/diffusion_pytorch_model.safetensors" \
         "models/controlnet" "flux-dev-controlnet-union.safetensors" "ControlNet Union Pro"

# E. Realism LoRA
download "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors" \
         "models/loras" "flux_realism.safetensors" "Realism LoRA"

# F. 4x-UltraSharp
download "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" \
         "models/upscale_models" "4x-UltraSharp.pth" "4x-UltraSharp"

# G. SigCLIP Vision
download "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
         "models/clip_vision" "sigclip_vision_patch14_384.safetensors" "SigCLIP Vision"

# H. XLabs IP-Adapter
download "https://huggingface.co/XLabs-AI/flux-ip-adapter/resolve/main/ip_adapter.safetensors" \
         "models/xlabs/ipadapters" "ip_adapter.safetensors" "XLabs IP-Adapter"

# ── ADIM 5: SYMLINK'LER ────────────────────────────────────────────
step "ADIM 5/6: Symlink'ler"
ln -sf "$COMFY_DIR/models/unet/flux1-dev-fp8.safetensors"          "$COMFY_DIR/models/diffusion_models/flux1-dev-fp8.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/clip/clip_l.safetensors"                  "$COMFY_DIR/models/text_encoders/clip_l.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/clip/t5xxl_fp8_e4m3fn.safetensors"        "$COMFY_DIR/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/xlabs/ipadapters/ip_adapter.safetensors"  "$COMFY_DIR/models/ipadapter/flux-ip-adapter.safetensors" 2>/dev/null || true
ok "Symlink'ler oluşturuldu"

# ── ADIM 6: DOĞRULAMA ──────────────────────────────────────────────
step "ADIM 6/6: Doğrulama"
ERRORS=0
verify() {
    local FILE="$1"
    local DESC="$2"
    if [ -f "$COMFY_DIR/$FILE" ]; then
        SIZE=$(du -h "$COMFY_DIR/$FILE" | cut -f1)
        ok "$DESC ($SIZE)"
    else
        fail "$DESC eksik → $FILE"
        ERRORS=$((ERRORS + 1))
    fi
}

verify "models/unet/flux1-dev-fp8.safetensors"                 "Flux Dev FP8"
verify "models/clip/clip_l.safetensors"                        "CLIP-L"
verify "models/clip/t5xxl_fp8_e4m3fn.safetensors"              "T5-XXL FP8"
verify "models/vae/ae.safetensors"                             "VAE"
verify "models/controlnet/flux-dev-controlnet-union.safetensors" "ControlNet Union Pro"
verify "models/loras/flux_realism.safetensors"                  "Realism LoRA"
verify "models/upscale_models/4x-UltraSharp.pth"               "4x-UltraSharp"
verify "models/clip_vision/sigclip_vision_patch14_384.safetensors" "SigCLIP Vision"
verify "models/xlabs/ipadapters/ip_adapter.safetensors"        "IP-Adapter"

echo ""
if [ $ERRORS -eq 0 ]; then
    ok "TÜM MODELLER DOĞRULANDI — SIFIR HATA!"
else
    fail "$ERRORS adet model eksik. Yukarıdaki listeyi kontrol et."
fi

# ── COMFYUI BAŞLAT ─────────────────────────────────────────────────
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui "cd $COMFY_DIR && python main.py --listen 0.0.0.0 --port 8188 --fast"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ KURULUM TAMAMLANDI!                                      ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Logları görmek için : tmux attach -t comfyui                ║${NC}"
echo -e "${GREEN}║  Çıkmak için         : Ctrl+B sonra D                        ║${NC}"
echo -e "${GREEN}║  Durdurmak için      : tmux kill-session -t comfyui          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
