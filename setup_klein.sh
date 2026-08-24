#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX.2 KLEIN 9B — RICH SETUP (setup_klein.sh)       ║
# ║  Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM               ║
# ║  İçerik         : 9B FP8 + Qwen3-8B + VAE + GGUF Q8_0           ║
# ║                   + Enhancer LoRA + UltraSharpV2                ║
# ║                   + Florence2 + EsesImageCompare + kjnodes      ║
# ║                   + Impact + Pixaroma + GGUF + essentials       ║
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
  fail "HF_TOKEN bulunamadı! Önce şunu çalıştırın:\n  export HF_TOKEN=hf_xxxxxxxxxxxxxxxx"
fi
HF_TOKEN="$(echo -n "$HF_TOKEN" | tr -d '[:space:]')"
export HF_TOKEN

CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${HF_TOKEN}" \
  "https://huggingface.co/api/models/black-forest-labs/FLUX.2-klein-9b-fp8" || echo "000")
if [ "$CODE" != "200" ]; then
  fail "Token gated modele erişemiyor (HTTP $CODE).\n  https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8 adresinden şartları onaylayın (Agree)."
fi
ok "HF_TOKEN geçerli (9B FP8 erişimi onaylandı)"

# ── 1. DİSK ───────────────────────────────────────────────────────
step "ADIM 1/10: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 70 ]; then
  fail "Sadece ${AVAIL}GB boş. Klein rich + GGUF paketi için en az 70GB önerilir!"
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 2. SİSTEM ─────────────────────────────────────────────────────
step "ADIM 2/10: Sistem Paketleri & Derleyiciler"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
  python3-venv python3-pip python3-dev build-essential gcc g++ \
  curl wget ca-certificates > /dev/null 2>&1 || true
ldconfig
ok "Sistem paketleri ve C derleyicileri kuruldu"

# ── 3. COMFYUI ────────────────────────────────────────────────────
step "ADIM 3/10: ComfyUI"
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" 2>/dev/null \
    || git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
else
  cd "$COMFY_DIR"
  git fetch --tags --quiet || true
  git checkout "$COMFY_TAG" 2>/dev/null || true
fi
ok "ComfyUI ($COMFY_TAG) hazır"

# ── 4. VENV + TORCH ───────────────────────────────────────────────
step "ADIM 4/10: Python venv + PyTorch"
cd "$COMFY_DIR"
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install -q --upgrade pip wheel setuptools
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q huggingface_hub einops timm 2>/dev/null || true
ok "venv + PyTorch (cu130) hazır"

# ── 5. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 5/10: Klasör Yapısı"
mkdir -p "$COMFY_DIR/models/"{diffusion_models,text_encoders,vae,loras,controlnet,upscale_models,clip_vision,ipadapter,unet}
mkdir -p "$COMFY_DIR/custom_nodes" "$COMFY_DIR/input" "$COMFY_DIR/output"
ok "Klasörler hazır"

# ── 6. CUSTOM NODES ───────────────────────────────────────────────
step "ADIM 6/10: Custom Node'lar"
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
  [ -f "${d}requirements.txt" ] && pip install -q -r "${d}requirements.txt" 2>/dev/null || true
done
ok "Custom node'lar kuruldu"

# ── 7. İNDİRME FONKSİYONU ─────────────────────────────────────────
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

  # ── 1) Python huggingface_hub API (Modern & Kesin Çözüm) ────────
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
    print(f'Hugging Face API Hatası: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
      if [ -f "$dest" ]; then
        find "$COMFY_DIR/$dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        ok "$label (hf_hub)"
        return 0
      fi
    fi
  fi

  # ── 2) aria2c (Düzeltilmiş Header Dizisi ile Yedek Yöntem) ─────
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

  # ── 3) curl (Son Çare) ──────────────────────────────────────────
  if [ -n "${HF_TOKEN:-}" ]; then
    curl -s -fL -H "Authorization: Bearer ${HF_TOKEN}" -o "$dest" "$url" 2>/dev/null && ok "$label (curl)" && return 0 || true
  else
    curl -s -fL -o "$dest" "$url" 2>/dev/null && ok "$label (curl)" && return 0 || true
  fi

  if [ "$is_gated" = true ]; then
    fail "$label indirilemedi! (Gated model – Token yetkisini ve repo erişim onayınızı kontrol edin)"
  else
    info "⚠️  $label indirilemedi (opsiyonel)"
    return 1
  fi
}

# ── 8. MODEL İNDİRMELERİ ──────────────────────────────────────────
step "ADIM 7/10: Model Paketleri İndiriliyor"

# Ana 9B Distilled FP8 (GATED)
download \
  "https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors" \
  "models/diffusion_models" "flux-2-klein-9b-fp8.safetensors" \
  "Klein 9B Distilled FP8" true

# GGUF Q8_0 (workflow için)
download \
  "https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q8_0.gguf" \
  "models/unet" "flux-2-klein-9b-Q8_0.gguf" \
  "Klein 9B GGUF Q8_0" false || true

# Text Encoder
download \
  "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
  "models/text_encoders" "qwen_3_8b_fp8mixed.safetensors" \
  "Qwen3-8B FP8 Text Encoder" false

# VAE
download \
  "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
  "models/vae" "flux2-vae.safetensors" \
  "Flux2 VAE" false

# Upscaler'lar
download \
  "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth" \
  "models/upscale_models" "4x-UltraSharp.pth" \
  "4x-UltraSharp" false || true

download \
  "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.pth" \
  "models/upscale_models" "4x-UltraSharpV2.pth" \
  "4x-UltraSharpV2" false || true

# Enhancer LoRA
download \
  "https://huggingface.co/reverentelusarca/detail-enhancer-flux-klein-9b/resolve/main/klein_9b_enhancer_v2.safetensors" \
  "models/loras" "klein_9b_enhancer_v2.safetensors" \
  "Klein 9B Enhancer v2 LoRA" false || true

# ── 9. İSİM EŞLEŞTİRME (symlink) ──────────────────────────────────
step "ADIM 8/10: Workflow İsim Uyumluluğu (symlink)"
ln -sf "$COMFY_DIR/models/diffusion_models/flux-2-klein-9b-fp8.safetensors" \
       "$COMFY_DIR/models/diffusion_models/flux-2-klein-9b.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
       "$COMFY_DIR/models/text_encoders/qwen_3_8b.safetensors" 2>/dev/null || true
ln -sf "$COMFY_DIR/models/unet/flux-2-klein-9b-Q8_0.gguf" \
       "$COMFY_DIR/models/diffusion_models/flux-2-klein-9b-Q8_0.gguf" 2>/dev/null || true
ok "Symlink'ler oluşturuldu (workflow isimleri uyumlu)"

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

verify "models/diffusion_models/flux-2-klein-9b-fp8.safetensors" "Klein 9B Distilled FP8"
verify "models/text_encoders/qwen_3_8b_fp8mixed.safetensors"     "Qwen3-8B Text Encoder"
verify "models/vae/flux2-vae.safetensors"                        "Flux2 VAE"

if [ $ERRORS -eq 0 ]; then
  ok "TÜM KRİTİK MODELLER DOĞRULANDI"
else
  fail "$ERRORS adet kritik model eksik!"
fi

# ── 11. BAŞLAT ────────────────────────────────────────────────────
step "ADIM 10/10: ComfyUI Başlatılıyor"
cd "$COMFY_DIR"
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui \
  "cd $COMFY_DIR && source venv/bin/activate && python main.py --listen 0.0.0.0 --port 8188 --highvram"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FLUX.2 KLEIN RICH KURULUM EKSİKSİZ TAMAMLANDI            ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Tag     : $COMFY_TAG                                       ║${NC}"
echo -e "${GREEN}║  Log     : tmux attach -t comfyui                            ║${NC}"
echo -e "${GREEN}║  Durdur  : tmux kill-session -t comfyui                      ║${NC}"
echo -e "${GREEN}║  Port    : 8188                                              ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Ana model : flux-2-klein-9b-fp8.safetensors                 ║${NC}"
echo -e "${GREEN}║  GGUF      : flux-2-klein-9b-Q8_0.gguf                        ║${NC}"
echo -e "${GREEN}║  TE        : qwen_3_8b_fp8mixed.safetensors                  ║${NC}"
echo -e "${GREEN}║  VAE       : flux2-vae.safetensors                           ║${NC}"
echo -e "${GREEN}║  Upscaler  : 4x-UltraSharp + UltraSharpV2                    ║${NC}"
echo -e "${GREEN}║  LoRA      : klein_9b_enhancer_v2                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}ComfyUI arka planda tmux içinde başlatıldı.${NC}"
echo -e "${CYAN}Logları izlemek için: tmux attach -t comfyui${NC}"
echo ""
