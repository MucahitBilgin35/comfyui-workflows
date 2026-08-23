#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║ COMFYUI + FLUX.2 KLEIN 9B/4B — FULL RICH SETUP (setup_klein.sh) ║
# ║ Son Güncelleme : 23 Ağustos 2026 (düzeltmeler eklendi)          ║
# ║ Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM                 ║
# ║ İçerik         : 9B Distilled + 9B Base + 4B + Qwen TE'ler       ║
# ║                + SeedVR2 + Detail LoRA + Face tools              ║
# ║                + controlnet_aux + Impact + Pixaroma + GGUF       ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

COMFY_DIR="/workspace/ComfyUI"
COMFY_TAG="v0.3.45"
TORCH_INDEX="https://download.pytorch.org/whl/cu124"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_ENDPOINT
export HF_HUB_ENABLE_HF_TRANSFER=1

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
  fail "Token gated modele erişemiyor (HTTP $CODE). Model lisansını (Agree) onayladığınızdan emin olun."
fi
ok "HF_TOKEN geçerli ve yetkili (HTTP 200)"

# Base model için de kontrol (opsiyonel ama tavsiye edilir)
CODE_BASE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${HF_TOKEN}" \
  "https://huggingface.co/api/models/black-forest-labs/FLUX.2-klein-base-9b-fp8" || echo "000")
if [ "$CODE_BASE" != "200" ]; then
  info "⚠️  Base 9B FP8 için lisans henüz onaylanmamış (HTTP $CODE_BASE). https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8 adresinden Agree yapın."
else
  ok "Base 9B FP8 lisansı da onaylı"
fi

# ── 1. DİSK ALANI KONTROLÜ ─────────────────────────────────────────
step "ADIM 1/9: Disk Alanı Kontrolü"
mkdir -p /workspace
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 50 ]; then
  fail "Sadece ${AVAIL}GB boş alan var. Rich Klein paketi için en az 50GB önerilir!"
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 2. SİSTEM PAKETLERİ ───────────────────────────────────────────
step "ADIM 2/9: Sistem Paketleri"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 \
  python3-venv python3-pip curl wget ca-certificates > /dev/null 2>&1 || true
ok "Sistem paketleri kuruldu"

# ── 3. COMFYUI KURULUMU ───────────────────────────────────────────
step "ADIM 3/9: ComfyUI Hazırlanıyor"
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR" 2>/dev/null \
    || git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
else
  cd "$COMFY_DIR"
  git fetch --tags --quiet || true
  git checkout "$COMFY_TAG" 2>/dev/null || true
fi
ok "ComfyUI kodları hazır"

# ── 4. PYTHON ORTAMI & PYTORCH ────────────────────────────────────
step "ADIM 4/9: Python venv ve PyTorch Kurulumu"
cd "$COMFY_DIR"
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install -q --upgrade pip wheel setuptools
pip install -q torch torchvision torchaudio --index-url "$TORCH_INDEX"
pip install -q -r requirements.txt
pip install -q huggingface_hub hf_transfer 2>/dev/null || true
ok "venv + PyTorch ortamı hazır"

# ── 5. KLASÖR YAPISI ──────────────────────────────────────────────
step "ADIM 5/9: Klasör Yapısı"
mkdir -p "$COMFY_DIR/models/"{diffusion_models,text_encoders,vae,loras,controlnet,upscale_models,clip_vision}
mkdir -p "$COMFY_DIR/custom_nodes" "$COMFY_DIR/input" "$COMFY_DIR/output"
ok "Model ve çalışma klasörleri hazır"

# ── 6. CUSTOM NODE'LAR ────────────────────────────────────────────
step "ADIM 6/9: Custom Node'lar Klonlanıyor"
cd "$COMFY_DIR/custom_nodes"

clone_node() {
  local name="$1" url="$2"
  if [ -d "$name" ]; then
    ok "$name zaten var"
  else
    info "$name indiriliyor..."
    git clone --depth 1 "$url" "$name" 2>/dev/null && ok "$name" || info "$name atlandı (hata)"
  fi
}

clone_node "ComfyUI-Manager"              "https://github.com/ltdrdata/ComfyUI-Manager.git"
clone_node "rgthree-comfy"                "https://github.com/rgthree/rgthree-comfy.git"
clone_node "ComfyUI-Impact-Pack"          "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_node "ComfyUI-Pixaroma"             "https://github.com/pixaroma/ComfyUI-Pixaroma.git"
clone_node "ComfyUI-GGUF"                 "https://github.com/city96/ComfyUI-GGUF.git"
clone_node "comfyui_controlnet_aux"       "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
clone_node "ComfyUI_essentials"           "https://github.com/cubiq/ComfyUI_essentials.git"
clone_node "one-node-flux-2-klein"        "https://github.com/yanokusnir-ai/one-node-flux-2-klein.git"
clone_node "ComfyUI-Flux2Klein-Enhancer"  "https://github.com/capitan01R/ComfyUI-Flux2Klein-Enhancer.git"
clone_node "Comfyui-flux2klein-Lora-loader" "https://github.com/capitan01R/Comfyui-flux2klein-Lora-loader.git"

# Bağımlılık kurulumları
if [ -f "ComfyUI-Impact-Pack/install.py" ]; then
  python "ComfyUI-Impact-Pack/install.py" 2>/dev/null || true
fi
for d in */; do
  if [ -f "${d}requirements.txt" ]; then
    pip install -q -r "${d}requirements.txt" 2>/dev/null || true
  fi
done
ok "Tüm custom node'lar kuruldu"

# ── 7. İNDİRME FONKSİYONU (ARIA2C + AUTH) ────────────────────────
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
  local auth_header=""
  if [ "$is_gated" = true ]; then
    auth_header="--header=Authorization: Bearer ${HF_TOKEN}"
  fi

  if aria2c -c -x 16 -s 16 -k 1M --console-log-level=error \
    --max-tries=5 --retry-wait=3 --timeout=60 --connect-timeout=20 \
    $auth_header "$url" -d "$COMFY_DIR/$dir" -o "$filename" 2>/dev/null; then
    ok "$label"
    return 0
  fi

  # Mirror fallback (Sadece public modeller için)
  if [ "$is_gated" = false ]; then
    local mirror_url="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
    if aria2c -c -x 16 -s 16 -k 1M --console-log-level=error \
      "$mirror_url" -d "$COMFY_DIR/$dir" -o "$filename" 2>/dev/null; then
      ok "$label (mirror)"
      return 0
    fi
  fi

  info "⚠️  $label indirilemedi (opsiyonel olabilir)"
  return 1
}

# ── 8. MODEL İNDİRMELERİ ──────────────────────────────────────────
step "ADIM 7/9: Ana ve Zengin Model Paketleri İndiriliyor"

# 1. Ana Distilled 9B (GATED)
download \
  "https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors" \
  "models/diffusion_models" "flux-2-klein-9b-fp8.safetensors" \
  "Klein 9B Distilled FP8" true

# 2. Base 9B (GATED) — lisans ayrı onaylanmalı
download \
  "https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors" \
  "models/diffusion_models" "flux-2-klein-base-9b-fp8.safetensors" \
  "Klein 9B Base FP8" true || true

# 3. Klein 4B Distilled
download \
  "https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/diffusion_models/flux-2-klein-4b.safetensors" \
  "models/diffusion_models" "flux-2-klein-4b.safetensors" \
  "Klein 4B Distilled" false || true

# 4. Text Encoders
download \
  "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
  "models/text_encoders" "qwen_3_8b_fp8mixed.safetensors" \
  "Qwen3-8B FP8 Text Encoder" false

download \
  "https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
  "models/text_encoders" "qwen_3_4b.safetensors" \
  "Qwen3-4B Text Encoder" false || true

# 5. VAE
download \
  "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
  "models/vae" "flux2-vae.safetensors" \
  "Flux2 VAE" false

# 6. Upscalers & SeedVR2  (DÜZELTİLDİ: doğru dosya adı)
download \
  "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
  "models/diffusion_models" "seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
  "SeedVR2 3B FP8" false || true

download \
  "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth" \
  "models/upscale_models" "4x-UltraSharp.pth" \
  "4x-UltraSharp" false || true

# 7. LoRA'lar & Ekstra Araçlar

# Realistic Detail LoRA (DÜZELTİLDİ: doğru dosya adı + URL encode)
download \
  "https://huggingface.co/SOLRICKS/Flux2-Klein-9B-Realistic-Detail/resolve/main/Flux2%20Klein%209B%20Realistic%20Detail%20LoRA.safetensors" \
  "models/loras" "flux2_klein_9b_srx_detail_lora.safetensors" \
  "Realistic Detail LoRA" false || true

# Base to Turbo LoRA (DÜZELTİLDİ: yeni repo + dosya adı)
download \
  "https://huggingface.co/anyMODE/Flux-2-Klein-Base-9B-to-turbo-lora/resolve/main/klein_9B_Turbo_r128.safetensors" \
  "models/loras" "klein_9b_base_to_turbo_r128.safetensors" \
  "Base to Turbo LoRA" false || true

# BFS Head Swap 9B (DÜZELTİLDİ: doğru dosya adı)
download \
  "https://huggingface.co/Alissonerdx/BFS-Best-Face-Swap/resolve/main/bfs_head_v1_flux-klein_9b_step3500_rank128.safetensors" \
  "models/loras" "BFS_Head_Swap_v1_9b.safetensors" \
  "BFS Head Swap 9B" false || true

# RefControl Depth LoRA
download \
  "https://huggingface.co/thedeoxen/refcontrol-FLUX.2-klein-9B-reference-depth-lora/resolve/main/flux2_klein_9b_refcontrol_depth.safetensors" \
  "models/loras" "flux2_klein_9b_refcontrol_depth.safetensors" \
  "RefControl Depth LoRA" false || true

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

verify "models/diffusion_models/flux-2-klein-9b-fp8.safetensors" "Klein 9B Distilled"
verify "models/text_encoders/qwen_3_8b_fp8mixed.safetensors"     "Qwen3-8B Text Encoder"
verify "models/vae/flux2-vae.safetensors"                        "Flux2 VAE"

if [ $ERRORS -eq 0 ]; then
  ok "TÜM KRİTİK MODELLER DOĞRULANDI"
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
echo -e "${GREEN}║  ✅ FLUX.2 KLEIN RICH KURULUM TAMAMLANDI                     ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Log     : tmux attach -t comfyui                            ║${NC}"
echo -e "${GREEN}║  Durdur  : tmux kill-session -t comfyui                      ║${NC}"
echo -e "${GREEN}║  Port    : 8188                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
