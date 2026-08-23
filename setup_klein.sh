#!/bin/bash
set -euo pipefail

COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.3.45"
TORCH_INDEX="https://download.pytorch.org/whl/cu124"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${YELLOW}══════════════════════════════════════════════════${NC}"; echo -e "${YELLOW} $1${NC}"; echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
fail()  { echo -e "  ${RED}❌ $1${NC}"; exit 1; }
info()  { echo -e "  ${CYAN}→ $1${NC}"; }

# ── 0. TOKEN ──────────────────────────────────────────────────────
step "ADIM 0/7: HF_TOKEN kontrol"
if [ -z "${HF_TOKEN:-}" ]; then
  fail "HF_TOKEN yok. export HF_TOKEN='hf_...' yapıp tekrar çalıştır."
fi
# sonda boşluk temizle
HF_TOKEN="$(echo -n "$HF_TOKEN" | tr -d '[:space:]')"
export HF_TOKEN
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${HF_TOKEN}" \
  "https://huggingface.co/api/models/black-forest-labs/FLUX.2-klein-9b-fp8" || echo "000")
if [ "$CODE" != "200" ]; then
  fail "Token gated modele erişemiyor (HTTP $CODE). Lisans Agree + token yetkisini kontrol et."
fi
ok "HF_TOKEN geçerli (HTTP 200)"

# ── 1. DISK ───────────────────────────────────────────────────────
step "ADIM 1/7: Disk"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ "${AVAIL:-0}" -lt 35 ]; then
  fail "Sadece ${AVAIL}GB boş. Minimum ~35GB önerilir."
fi
ok "Disk: ${AVAIL}GB"

# ── 2. SİSTEM ─────────────────────────────────────────────────────
step "ADIM 2/7: Sistem paketleri"
apt-get update -qq
apt-get install -y -qq git git-lfs curl wget ca-certificates aria2 tmux ffmpeg \
  libgl1 libglib2.0-0 python3-venv python3-pip > /dev/null 2>&1 || true
ok "Sistem paketleri"

# ── 3. COMFYUI ────────────────────────────────────────────────────
step "ADIM 3/7: ComfyUI ${COMFY_TAG}"
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR" \
    || git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
fi
cd "$COMFY_DIR"
python3 -m venv venv
source venv/bin/activate
pip install -q --upgrade pip wheel
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q huggingface_hub
ok "ComfyUI + venv + torch"

# ── 4. CUSTOM NODES ───────────────────────────────────────────────
step "ADIM 4/7: Custom nodes"
mkdir -p custom_nodes
cd custom_nodes

clone_node() {
  local url="$1" name="$2"
  if [ -d "$name" ]; then
    info "$name zaten var"
  else
    git clone --depth 1 "$url" "$name" || info "$name clone atlandı"
  fi
}

clone_node "https://github.com/ltdrdata/ComfyUI-Manager.git" "ComfyUI-Manager"
clone_node "https://github.com/city96/ComfyUI-GGUF.git" "ComfyUI-GGUF"
clone_node "https://github.com/rgthree/rgthree-comfy.git" "rgthree-comfy"
clone_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" "ComfyUI-Impact-Pack"
clone_node "https://github.com/Fannovel16/comfyui_controlnet_aux.git" "comfyui_controlnet_aux"
clone_node "https://github.com/cubiq/ComfyUI_essentials.git" "ComfyUI_essentials"

# node requirements (sessiz)
for d in ComfyUI-Manager ComfyUI-GGUF ComfyUI-Impact-Pack comfyui_controlnet_aux ComfyUI_essentials; do
  if [ -f "$d/requirements.txt" ]; then
    pip install -q -r "$d/requirements.txt" 2>/dev/null || true
  fi
done
ok "Custom nodes"

# ── 5. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 5/7: Model klasörleri"
cd "$COMFY_DIR"
mkdir -p models/{diffusion_models,text_encoders,vae,loras,upscale_models,clip_vision,controlnet}
ok "Klasörler hazır"

# ── 6. MODELLER ───────────────────────────────────────────────────
step "ADIM 6/7: Modeller"

dl_public() {
  local url="$1" dest="$2" label="$3"
  if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" -gt 1000000 ]; then
    ok "$label (mevcut)"
    return 0
  fi
  info "İndiriliyor: $label"
  curl -L --http1.1 --retry 3 --retry-delay 5 \
    -o "$dest" "$url" || fail "$label indirilemedi"
  ok "$label"
}

dl_gated() {
  local url="$1" dest="$2" label="$3"
  if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" -gt 1000000000 ]; then
    ok "$label (mevcut)"
    return 0
  fi
  info "İndiriliyor (gated): $label"
  curl -L --http1.1 --retry 3 --retry-delay 5 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    -o "$dest" "$url" || fail "$label indirilemedi — token/lisans kontrol et"
  local sz
  sz=$(stat -c%s "$dest" 2>/dev/null || echo 0)
  if [ "$sz" -lt 1000000000 ]; then
    fail "$label çok küçük ($sz byte) — indirme bozulmuş olabilir"
  fi
  ok "$label ($(numfmt --to=iec "$sz" 2>/dev/null || echo "$sz"))"
}

# Ana diffusion (BFL gated)
dl_gated \
  "https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors" \
  "$COMFY_DIR/models/diffusion_models/flux-2-klein-9b-fp8.safetensors" \
  "Klein 9B Distilled FP8"

# Text encoder (public)
dl_public \
  "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
  "$COMFY_DIR/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
  "Qwen3-8B FP8"

# VAE (public)
dl_public \
  "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
  "$COMFY_DIR/models/vae/flux2-vae.safetensors" \
  "flux2-vae"

ok "Kritik modeller tamam"

# ── 7. BAŞLAT ─────────────────────────────────────────────────────
step "ADIM 7/7: ComfyUI başlat"
cd "$COMFY_DIR"
source venv/bin/activate
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
  "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ KLEIN KURULUM TAMAMLANDI                                 ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Model   : flux-2-klein-9b-fp8.safetensors                   ║${NC}"
echo -e "${GREEN}║  TE      : qwen_3_8b_fp8mixed.safetensors (type=flux2)       ║${NC}"
echo -e "${GREEN}║  VAE     : flux2-vae.safetensors                             ║${NC}"
echo -e "${GREEN}║  Steps   : 4   CFG: 1.0–1.5                                  ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Log     : tmux attach -t comfyui                            ║${NC}"
echo -e "${GREEN}║  Durdur  : tmux kill-session -t comfyui                      ║${NC}"
echo -e "${GREEN}║  Port    : 8188                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
