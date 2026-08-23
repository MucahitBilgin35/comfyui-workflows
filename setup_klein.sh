#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX.2 KLEIN 9B — RICH SETUP (setup_klein.sh)       ║
# ║  Son Güncelleme : 23 Ağustos 2026                               ║
# ║  Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM               ║
# ║  İçerik         : 9B Distilled + 9B Base + 4B + Qwen TE'ler    ║
# ║                   + SeedVR2 + Detail LoRA + Face tools          ║
# ║                   + controlnet_aux + Impact + Pixaroma + GGUF   ║
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
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 55 ]; then
    fail "Sadece ${AVAIL}GB boş. Rich Klein paketi için minimum 55GB önerilir!"
    exit 1
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 1. SİSTEM ─────────────────────────────────────────────────────
step "ADIM 1/9: Sistem Paketleri"
apt-get update -qq
apt-get install -y -qq git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 > /dev/null 2>&1 || true
ok "Sistem paketleri kuruldu"

# ── 2. COMFYUI ────────────────────────────────────────────────────
step "ADIM 2/9: ComfyUI (pin: $COMFY_TAG)"
if [ ! -d "$COMFY_DIR/.git" ]; then
    git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" \
        || git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
else
    cd "$COMFY_DIR"
    git fetch --tags
    git checkout "$COMFY_TAG" 2>/dev/null || true
fi
ok "ComfyUI hazır"

# ── 3. VENV + TORCH ───────────────────────────────────────────────
step "ADIM 3/9: Python venv + PyTorch"
cd "$COMFY_DIR"
python3 -m venv venv
source venv/bin/activate
pip install -q --upgrade pip wheel
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q hf_transfer 2>/dev/null || true
ok "venv + torch kuruldu"

# ── 4. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 4/9: Klasör Yapısı"
mkdir -p "$COMFY_DIR/models/diffusion_models"
mkdir -p "$COMFY_DIR/models/text_encoders"
mkdir -p "$COMFY_DIR/models/vae"
mkdir -p "$COMFY_DIR/models/loras"
mkdir -p "$COMFY_DIR/models/controlnet"
mkdir -p "$COMFY_DIR/models/upscale_models"
mkdir -p "$COMFY_DIR/models/clip_vision"
mkdir -p "$COMFY_DIR/custom_nodes"
mkdir -p "$COMFY_DIR/input" "$COMFY_DIR/output"
ok "Klasörler hazır"

# ── 5. CUSTOM NODES ───────────────────────────────────────────────
step "ADIM 5/9: Custom Nodes"
cd "$COMFY_DIR/custom_nodes"

clone_node() {
    local name="$1" url="$2"
    if [ -d "$name" ]; then
        info "$name zaten var"
    else
        git clone --depth 1 "$url" "$name" && ok "$name" || fail "$name klonlanamadı"
    fi
}

clone_node "ComfyUI-Manager"              "https://github.com/ltdrdata/ComfyUI-Manager.git"
clone_node "rgthree-comfy"                "https://github.com/rgthree/rgthree-comfy.git"
clone_node "ComfyUI-Impact-Pack"          "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_node "ComfyUI-Pixaroma"             "https://github.com/pixaroma/ComfyUI-Pixaroma.git"
clone_node "ComfyUI-GGUF"                 "https://github.com/city96/ComfyUI-GGUF.git"
clone_node "comfyui_controlnet_aux"       "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
clone_node "one-node-flux-2-klein"        "https://github.com/yanokusnir-ai/one-node-flux-2-klein.git"
clone_node "ComfyUI-Flux2Klein-Enhancer"  "https://github.com/capitan01R/ComfyUI-Flux2Klein-Enhancer.git"
clone_node "Comfyui-flux2klein-Lora-loader" "https://github.com/capitan01R/Comfyui-flux2klein-Lora-loader.git"

# Impact Pack bağımlılıkları
if [ -f "ComfyUI-Impact-Pack/install.py" ]; then
    python "ComfyUI-Impact-Pack/install.py" 2>/dev/null || true
fi
if [ -f "comfyui_controlnet_aux/requirements.txt" ]; then
    pip install -q -r comfyui_controlnet_aux/requirements.txt 2>/dev/null || true
fi

ok "Custom nodes tamam"

# ── 6. İNDİRME FONKSİYONU ─────────────────────────────────────────
download() {
    local url="$1" dir="$2" filename="$3" label="$4"
    local dest="$COMFY_DIR/$dir/$filename"
    mkdir -p "$COMFY_DIR/$dir"
    if [ -f "$dest" ] && [ -s "$dest" ]; then
        ok "$label zaten var"
        return 0
    fi
    info "İndiriliyor: $label"
    local mirror_url="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
    if aria2c -x 16 -s 16 -k 1M --console-log-level=warn -c -d "$COMFY_DIR/$dir" -o "$filename" "$mirror_url" 2>/dev/null; then
        ok "$label"
        return 0
    fi
    if aria2c -x 16 -s 16 -k 1M --console-log-level=warn -c -d "$COMFY_DIR/$dir" -o "$filename" "$url" 2>/dev/null; then
        ok "$label (orijinal HF)"
        return 0
    fi
    fail "$label indirilemedi"
    return 1
}

# ── 7. ANA MODELLER ───────────────────────────────────────────────
step "ADIM 6/9: Ana Klein Modelleri"

# Distilled 9B (4-step ana model)
download \
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors" \
    "models/diffusion_models" "flux-2-klein-9b-fp8.safetensors" \
    "Klein 9B Distilled FP8"

# Base 9B (LoRA / esnek)
download \
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors" \
    "models/diffusion_models" "flux-2-klein-base-9b-fp8.safetensors" \
    "Klein 9B Base FP8"

# Klein 4B Distilled (karşılaştırma + Apache 2.0)
download \
    "https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/diffusion_models/flux-2-klein-4b.safetensors" \
    "models/diffusion_models" "flux-2-klein-4b.safetensors" \
    "Klein 4B Distilled" \
|| download \
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8/resolve/main/flux-2-klein-4b-fp8.safetensors" \
    "models/diffusion_models" "flux-2-klein-4b-fp8.safetensors" \
    "Klein 4B FP8"

# Text Encoder 9B
download \
    "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
    "models/text_encoders" "qwen_3_8b_fp8mixed.safetensors" \
    "Qwen3-8B FP8 mixed"

# Text Encoder 4B
download \
    "https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
    "models/text_encoders" "qwen_3_4b.safetensors" \
    "Qwen3-4B"

# VAE
download \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
    "models/vae" "flux2-vae.safetensors" \
    "Flux2 VAE"

ok "Ana modeller tamam"

# ── 8. UPSCALE + DETAIL ───────────────────────────────────────────
step "ADIM 7/9: Upscale + Detail + LoRA"

# SeedVR2 3B FP8 (Klein workflow'larında en çok kullanılan upscaler)
download \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp8.safetensors" \
    "models/diffusion_models" "seedvr2_ema_3b_fp8.safetensors" \
    "SeedVR2 3B FP8" \
|| download \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b.safetensors" \
    "models/diffusion_models" "seedvr2_ema_3b.safetensors" \
    "SeedVR2 3B"

# Klasik 4x upscaler
download \
    "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth" \
    "models/upscale_models" "4x-UltraSharp.pth" \
    "4x-UltraSharp"

# Realistic Detail LoRA (Klein 9B)
download \
    "https://huggingface.co/SOLRICKS/Flux2-Klein-9B-Realistic-Detail/resolve/main/flux2_klein_9b_srx_detail_lora.safetensors" \
    "models/loras" "flux2_klein_9b_srx_detail_lora.safetensors" \
    "Realistic Detail LoRA (srx_detail)"

# Base → Turbo tarzı hızlandırma LoRA (Base kullanırken)
download \
    "https://huggingface.co/anyMODE/Klein-Base-to-Turbo-LoRA/resolve/main/klein_9b_base_to_turbo_r128.safetensors" \
    "models/loras" "klein_9b_base_to_turbo_r128.safetensors" \
    "Base→Turbo LoRA r128" \
|| info "Base→Turbo LoRA atlandı (link değişmiş olabilir)"

# Style örnekleri (hafif)
download \
    "https://huggingface.co/DeverStyle/Flux.2-Klein-Loras/resolve/main/dvr_tldr_style.safetensors" \
    "models/loras" "dvr_tldr_style.safetensors" \
    "Teal Dark style LoRA" \
|| info "Style LoRA atlandı"

# Face / Head Swap (BFS community)
download \
    "https://huggingface.co/Alissonerdx/BFS-Best-Face-Swap/resolve/main/BFS_Head_Swap_v1_9b.safetensors" \
    "models/loras" "BFS_Head_Swap_v1_9b.safetensors" \
    "BFS Head Swap 9B" \
|| download \
    "https://huggingface.co/botp/BFS-Best-Face-Swap/resolve/main/BFS_Head_Swap_v1_9b.safetensors" \
    "models/loras" "BFS_Head_Swap_v1_9b.safetensors" \
    "BFS Head Swap 9B (alt)" \
|| info "Face Swap LoRA atlandı"

# RefControl depth (reference + depth)
download \
    "https://huggingface.co/thedeoxen/refcontrol-FLUX.2-klein-9B-reference-depth-lora/resolve/main/flux2_klein_9b_refcontrol_depth.safetensors" \
    "models/loras" "flux2_klein_9b_refcontrol_depth.safetensors" \
    "RefControl Depth LoRA" \
|| info "RefControl Depth atlandı"

ok "Upscale + LoRA tamam"

# ── 9. DOĞRULAMA ──────────────────────────────────────────────────
step "ADIM 8/9: Doğrulama"
ERRORS=0
verify() {
    local path="$1" name="$2"
    if [ -f "$COMFY_DIR/$path" ] && [ -s "$COMFY_DIR/$path" ]; then
        ok "$name"
    else
        fail "$name EKSİK → $path"
        ERRORS=$((ERRORS+1))
    fi
}

verify "models/diffusion_models/flux-2-klein-9b-fp8.safetensors" "Klein 9B Distilled"
verify "models/text_encoders/qwen_3_8b_fp8mixed.safetensors"     "Qwen3-8B"
verify "models/vae/flux2-vae.safetensors"                        "Flux2 VAE"

echo ""
info "Opsiyonel dosyalar (eksik olsa da script devam eder):"
[ -f "$COMFY_DIR/models/diffusion_models/flux-2-klein-base-9b-fp8.safetensors" ] && ok "Klein 9B Base" || info "Klein 9B Base yok"
[ -f "$COMFY_DIR/models/diffusion_models/flux-2-klein-4b.safetensors" ] || [ -f "$COMFY_DIR/models/diffusion_models/flux-2-klein-4b-fp8.safetensors" ] && ok "Klein 4B" || info "Klein 4B yok"
[ -f "$COMFY_DIR/models/text_encoders/qwen_3_4b.safetensors" ] && ok "Qwen3-4B" || info "Qwen3-4B yok"
[ -f "$COMFY_DIR/models/diffusion_models/seedvr2_ema_3b_fp8.safetensors" ] || [ -f "$COMFY_DIR/models/diffusion_models/seedvr2_ema_3b.safetensors" ] && ok "SeedVR2" || info "SeedVR2 yok"
[ -f "$COMFY_DIR/models/loras/flux2_klein_9b_srx_detail_lora.safetensors" ] && ok "Detail LoRA" || info "Detail LoRA yok"

echo ""
if [ $ERRORS -eq 0 ]; then
    ok "KRİTİK MODELLER TAMAM"
else
    fail "$ERRORS kritik eksik — BFL gated için: export HF_TOKEN=hf_xxx"
fi

# ── 10. BAŞLAT ────────────────────────────────────────────────────
step "ADIM 9/9: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
    "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FLUX.2 KLEIN RICH KURULUM TAMAMLANDI                     ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Tag     : $COMFY_TAG                                       ║${NC}"
echo -e "${GREEN}║  Log     : tmux attach -t comfyui                            ║${NC}"
echo -e "${GREEN}║  Durdur  : tmux kill-session -t comfyui                      ║${NC}"
echo -e "${GREEN}║  Port    : 8188                                              ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Ana     : flux-2-klein-9b-fp8  (4 step, CFG 1.0–1.5)       ║${NC}"
echo -e "${GREEN}║  CLIP    : type = flux2   |  TE = qwen_3_8b_fp8mixed         ║${NC}"
echo -e "${GREEN}║  VAE     : flux2-vae                                         ║${NC}"
echo -e "${GREEN}║  Extra   : Base 9B · 4B · SeedVR2 · Detail/Style/Face LoRA  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Kullanım özeti:${NC}"
echo -e "  Distilled 9B → steps=4, cfg=1.0–1.5, CLIPLoader type=flux2"
echo -e "  Base 9B      → steps≈20–50, cfg≈3.5–5"
echo -e "  Detail LoRA  → trigger: srx_detail, strength 0.6–0.8"
echo -e "  EmptyFlux2LatentImage kullan (EmptyLatentImage değil)"
echo ""
echo -e "${CYAN}Flux.1 → setup_full.sh / setup_weekend.sh${NC}"
echo -e "${CYAN}Flux.2 Klein → setup_klein.sh (bu script)${NC}"
echo ""
