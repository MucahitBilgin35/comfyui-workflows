#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  COMFYUI + FLUX.1 DEV — EXTRAS (setup_fluxDev1Extras.sh)        ║
# ║  Son Güncelleme : 25 Ağustos 2026                               ║
# ║  Hedef GPU      : RTX 3090 / 4090 + min 64 GB RAM               ║
# ║  İçerik         : PuLID + IC-Light + UltimateSDUpscale + SUPIR  ║
# ║                   + SAM2 + Inpaint-CropAndStitch + ReActor      ║
# ║                   + KJNodes + tüm gerekli modeller              ║
# ║  Bağımlılık     : setup_weekend.sh (veya eşdeğer base) kurulu   ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

COMFY_DIR="/workspace/ComfyUI"
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

# ── 0. ÖN KONTROL ─────────────────────────────────────────────────
step "ADIM 0/10: Ön Kontroller"
if [ ! -d "$COMFY_DIR" ] || [ ! -d "$COMFY_DIR/venv" ]; then
    fail "ComfyUI veya venv bulunamadı! Önce setup_weekend.sh (veya base kurulum) çalıştır."
    exit 1
fi
cd "$COMFY_DIR"
source venv/bin/activate
ok "ComfyUI + venv hazır"

# Disk kontrolü (ekstra paket için)
AVAIL=$(df -BG /workspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 35 ]; then
    fail "Sadece ${AVAIL}GB boş. Extras paketi için minimum 35GB önerilir!"
    exit 1
fi
ok "Disk alanı yeterli: ${AVAIL:-?}GB"

# ── 1. SİSTEM + PYTHON BAĞIMLILIKLARI ─────────────────────────────
step "ADIM 1/10: Sistem + Python Bağımlılıkları (PuLID/ReActor/SAM için)"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    unzip libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    > /dev/null 2>&1 || true

# Kritik pip paketleri (çakışmayı minimize etmek için sırayla)
pip install --quiet --upgrade pip wheel setuptools
pip install --quiet insightface onnxruntime-gpu facexlib opencv-python-headless
pip install --quiet open-clip-torch timm filterpy scikit-image
# ReActor / yeni core için
pip install --quiet numpy --upgrade || true
ok "Python bağımlılıkları kuruldu"

# ── 2. CUSTOM NODE'LAR ────────────────────────────────────────────
step "ADIM 2/10: Custom Node'lar (Extras)"
mkdir -p custom_nodes
cd custom_nodes

declare -A NODES=(
    ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
    ["ComfyUI-IC-Light"]="https://github.com/kijai/ComfyUI-IC-Light.git"
    ["ComfyUI_UltimateSDUpscale"]="https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
    ["ComfyUI-SUPIR"]="https://github.com/kijai/ComfyUI-SUPIR.git"
    ["ComfyUI-segment-anything-2"]="https://github.com/kijai/ComfyUI-segment-anything-2.git"
    ["ComfyUI-Inpaint-CropAndStitch"]="https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"
    ["ComfyUI_PuLID_Flux_ll"]="https://github.com/lldacing/ComfyUI_PuLID_Flux_ll.git"
    ["ComfyUI-ReActor"]="https://github.com/Gourieff/ComfyUI-ReActor.git"
)

for name in "${!NODES[@]}"; do
    if [ -d "$name" ]; then
        ok "$name mevcut"
    else
        info "$name klonlanıyor..."
        if git clone --depth=1 "${NODES[$name]}" "$name" 2>/dev/null; then
            ok "$name"
        else
            fail "$name klonlanamadı (devam ediliyor)"
        fi
    fi
done

# Her node'un requirements'ını kur
for req in */requirements.txt; do
    [ -f "$req" ] || continue
    info "pip install -r $req"
    pip install --quiet -r "$req" 2>/dev/null || true
done

# PuLID özel ekstra
if [ -d "ComfyUI_PuLID_Flux_ll" ]; then
    pip install --quiet facenet-pytorch --no-deps 2>/dev/null || true
fi

ok "Custom node'lar hazır"
cd "$COMFY_DIR"

# ── 3. KLASÖRLER ──────────────────────────────────────────────────
step "ADIM 3/10: Ek Klasörler"
mkdir -p models/{pulid,insightface/models/antelopev2,unet/IC-Light,supir,sam2,facerestore_models,hyperswap,reswapper}
mkdir -p models/checkpoints   # SUPIR + olası SDXL base için
ok "Klasörler hazır"

# ── 4. İNDİRME FONKSİYONU (orijinalle aynı) ───────────────────────
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

# ── 5. PuLID MODELLERİ ────────────────────────────────────────────
step "ADIM 4/10: PuLID (Identity Consistency)"
download \
    "https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors" \
    "models/pulid" "pulid_flux_v0.9.1.safetensors" \
    "PuLID Flux v0.9.1 (~1.14 GB)"

# Antelopev2 (InsightFace) — zip olarak indirip çıkar
ANTELOPE_DIR="models/insightface/models/antelopev2"
if [ ! -f "$ANTELOPE_DIR/1k3d68.onnx" ]; then
    info "Antelopev2 indiriliyor + çıkarılıyor..."
    mkdir -p models/insightface/models
    TEMP_ZIP="/tmp/antelopev2.zip"
    if aria2c -c -x 8 -s 8 -k 1M --console-log-level=error \
        "https://huggingface.co/MonsterMMORPG/tools/resolve/main/antelopev2.zip" \
        -d /tmp -o antelopev2.zip 2>/dev/null || \
       aria2c -c -x 8 -s 8 -k 1M --console-log-level=error \
        "https://hf-mirror.com/MonsterMMORPG/tools/resolve/main/antelopev2.zip" \
        -d /tmp -o antelopev2.zip; then
        unzip -qo "$TEMP_ZIP" -d models/insightface/models/
        # Nested klasör düzeltmesi
        if [ -d "models/insightface/models/antelopev2/antelopev2" ]; then
            mv models/insightface/models/antelopev2/antelopev2/* models/insightface/models/antelopev2/
            rmdir models/insightface/models/antelopev2/antelopev2 2>/dev/null || true
        fi
        rm -f "$TEMP_ZIP"
        ok "Antelopev2 (InsightFace)"
    else
        fail "Antelopev2 indirilemedi — PuLID InsightFace loader çalışmayabilir (FaceNet alternatifini kullan)"
    fi
else
    ok "Antelopev2 zaten var"
fi

# EVA-CLIP çoğu zaman otomatik iner, yine de yedek
download \
    "https://huggingface.co/QuanSun/EVA-CLIP/resolve/main/EVA02_CLIP_L_336_psz14_s6B.pt" \
    "models/clip" "EVA02_CLIP_L_336_psz14_s6B.pt" \
    "EVA-CLIP L/14-336 (PuLID)" || true

ok "PuLID paket tamam"

# ── 6. IC-LIGHT ───────────────────────────────────────────────────
step "ADIM 5/10: IC-Light (Relighting)"
download \
    "https://huggingface.co/lllyasviel/ic-light/resolve/main/iclight_sd15_fc.safetensors" \
    "models/unet/IC-Light" "iclight_sd15_fc.safetensors" \
    "IC-Light FC (text+foreground)"
download \
    "https://huggingface.co/lllyasviel/ic-light/resolve/main/iclight_sd15_fbc.safetensors" \
    "models/unet/IC-Light" "iclight_sd15_fbc.safetensors" \
    "IC-Light FBC (text+foreground+background)" || true
# Symlink kolay erişim için
ln -sf "$COMFY_DIR/models/unet/IC-Light/iclight_sd15_fc.safetensors" \
       "$COMFY_DIR/models/unet/iclight_sd15_fc.safetensors" 2>/dev/null || true
ok "IC-Light modelleri hazır"

# ── 7. SUPIR ──────────────────────────────────────────────────────
step "ADIM 6/10: SUPIR (High-quality Upscale)"
download \
    "https://huggingface.co/Kijai/SUPIR_pruned/resolve/main/SUPIR-v0Q_fp16.safetensors" \
    "models/checkpoints" "SUPIR-v0Q_fp16.safetensors" \
    "SUPIR-v0Q FP16 (Quality)" || \
download \
    "https://huggingface.co/Kijai/SUPIR_pruned/resolve/main/SUPIR-v0Q_fp16.safetensors" \
    "models/supir" "SUPIR-v0Q_fp16.safetensors" \
    "SUPIR-v0Q FP16 (alternatif yol)"

download \
    "https://huggingface.co/Kijai/SUPIR_pruned/resolve/main/SUPIR-v0F_fp16.safetensors" \
    "models/checkpoints" "SUPIR-v0F_fp16.safetensors" \
    "SUPIR-v0F FP16 (Fidelity)" || true

# Not: SUPIR için bir SDXL base gerekir. Yoksa kullanıcı kendi indirmeli.
# Örnek hafif bir tane (opsiyonel, yorum satırı)
# download "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
#     "models/checkpoints" "sd_xl_base_1.0.safetensors" "SDXL Base (SUPIR için)"

ok "SUPIR modelleri hazır (SDXL base ayrı gerekebilir)"

# ── 8. SAM2 + REACTOR + DİĞER ─────────────────────────────────────
step "ADIM 7/10: SAM2 + ReActor + Yardımcı Modeller"
# SAM2 modelleri Kijai node'u tarafından otomatik indirilir (models/sam2)
# Yine de en çok kullanılanı manuel koyalım
download \
    "https://huggingface.co/Kijai/sam2-safetensors/resolve/main/sam2_hiera_large.safetensors" \
    "models/sam2" "sam2_hiera_large.safetensors" \
    "SAM2 Hiera Large" || true

# ReActor inswapper
download \
    "https://huggingface.co/ezioruan/inswapper_128/resolve/main/inswapper_128.onnx" \
    "models/insightface" "inswapper_128.onnx" \
    "ReActor inswapper_128" || true

# Face restore (ReActor + Impact ile kullanılır)
download \
    "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.4/GFPGANv1.4.pth" \
    "models/facerestore_models" "GFPGANv1.4.pth" \
    "GFPGAN v1.4" || true

ok "SAM2 + ReActor yardımcı modeller tamam"

# ── 9. DOĞRULAMA ──────────────────────────────────────────────────
step "ADIM 8/10: Doğrulama"
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

verify "models/pulid/pulid_flux_v0.9.1.safetensors"                 "PuLID Flux v0.9.1"
verify "models/insightface/models/antelopev2/1k3d68.onnx"           "Antelopev2 (1k3d68)"
verify "models/unet/IC-Light/iclight_sd15_fc.safetensors"           "IC-Light FC"
verify "models/checkpoints/SUPIR-v0Q_fp16.safetensors"              "SUPIR-v0Q" || \
verify "models/supir/SUPIR-v0Q_fp16.safetensors"                    "SUPIR-v0Q (alt)"
verify "custom_nodes/ComfyUI_PuLID_Flux_ll"                         "PuLID node (klasör)"
verify "custom_nodes/ComfyUI-IC-Light"                              "IC-Light node"
verify "custom_nodes/ComfyUI_UltimateSDUpscale"                     "UltimateSDUpscale"
verify "custom_nodes/ComfyUI-SUPIR"                                 "SUPIR node"
verify "custom_nodes/ComfyUI-segment-anything-2"                    "SAM2 node"
verify "custom_nodes/ComfyUI-Inpaint-CropAndStitch"                 "Inpaint Crop&Stitch"
verify "custom_nodes/ComfyUI-ReActor"                               "ReActor"
verify "custom_nodes/ComfyUI-KJNodes"                               "KJNodes"

echo ""
if [ $ERRORS -eq 0 ]; then
    ok "TÜM KRİTİK EXTRAS TAMAM"
else
    fail "$ERRORS eksik — log'a bak, gerekirse tekrar çalıştır"
fi

# ── 10. BİTİŞ ─────────────────────────────────────────────────────
step "ADIM 9/10: Temizlik + Bilgilendirme"
# Gereksiz cache temizliği
find models -name "*.tmp" -delete 2>/dev/null || true
ok "Temizlik yapıldı"

step "ADIM 10/10: Kurulum Özeti"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FLUX.1 DEV EXTRAS KURULUMU TAMAMLANDI                    ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Eklenenler:                                                 ║${NC}"
echo -e "${GREEN}║  • PuLID Flux v0.9.1 + Antelopev2 + EVA-CLIP                 ║${NC}"
echo -e "${GREEN}║  • IC-Light (FC + FBC)                                       ║${NC}"
echo -e "${GREEN}║  • Ultimate SD Upscale                                       ║${NC}"
echo -e "${GREEN}║  • SUPIR (v0Q + v0F FP16)                                    ║${NC}"
echo -e "${GREEN}║  • SAM2 (Kijai)                                              ║${NC}"
echo -e "${GREEN}║  • Inpaint Crop & Stitch                                     ║${NC}"
echo -e "${GREEN}║  • ReActor (yüz swap)                                        ║${NC}"
echo -e "${GREEN}║  • KJNodes                                                   ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Sonraki adım:                                               ║${NC}"
echo -e "${GREEN}║  1. ComfyUI'yi yeniden başlat (tmux kill + new)              ║${NC}"
echo -e "${GREEN}║  2. Manager → Update All (önerilir)                          ║${NC}"
echo -e "${GREEN}║  3. SUPIR için bir SDXL base model lazım (yoksa indir)       ║${NC}"
echo -e "${GREEN}║  4. PuLID workflow'larında FaceNet loader'ı tercih et        ║${NC}"
echo -e "${GREEN}║     (ticari kullanım için)                                   ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Not: I2V hâlâ ayrı aşama (CogVideo / LTX / vb. sonra)       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Base kurulum   → setup_weekend.sh${NC}"
echo -e "${CYAN}Extras         → setup_fluxDev1Extras.sh (bu script)${NC}"
echo ""
