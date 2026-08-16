#!/bin/bash
set -e

echo "======================================================"
echo "   FLUX DEV & COMFYUI OTOMATİK KURULUM BAŞLATILIYOR    "
echo "======================================================"

# 1. Hızlı İndirme Araçlarını Kur ve Aktif Et
echo "[1/5] Hızlı indirme altyapısı (hf_transfer & aria2) kuruluyor..."
apt-get update -qq && apt-get install -y -qq aria2 git-lfs > /dev/null 2>&1 || true
pip install -q -U pip
pip install -q hf_transfer huggingface_hub

# Hugging Face çoklu bağlantı (multi-thread) hızlandırıcısını aç
export HF_HUB_ENABLE_HF_TRANSFER=1

# ComfyUI Dizinini Belirle (Clore / RunPod standart dizini)
COMFY_DIR="/workspace/ComfyUI"
if [ ! -d "$COMFY_DIR" ]; then
    if [ -d "/root/ComfyUI" ]; then
        COMFY_DIR="/root/ComfyUI"
    else
        echo "ComfyUI bulunamadı, sıfırdan klonlanıyor..."
        git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
        COMFY_DIR="/workspace/ComfyUI"
    fi
fi

cd $COMFY_DIR

# 2. Temel ve Vazgeçilmez Custom Node'ları Paralel Olarak Klonla
echo "[2/5] Temel Custom Node'lar kuruluyor..."
mkdir -p custom_nodes
cd custom_nodes

git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git 2>/dev/null || (cd ComfyUI-Manager && git pull) &
git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git 2>/dev/null || (cd rgthree-comfy && git pull) &
git clone --depth=1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git 2>/dev/null || (cd ComfyUI-Custom-Scripts && git pull) &
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git 2>/dev/null || (cd ComfyUI-Impact-Pack && git pull) &
git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git 2>/dev/null || (cd comfyui_controlnet_aux && git pull) &
git clone --depth=1 https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git 2>/dev/null || (cd ComfyUI_Comfyroll_CustomNodes && git pull) &
wait

# Node bağımlılıklarını kur
pip install -q -r ComfyUI-Impact-Pack/requirements.txt || true
pip install -q -r comfyui_controlnet_aux/requirements.txt || true

# 3. Model Dizinlerini Hazırla
cd $COMFY_DIR
mkdir -p models/checkpoints models/clip models/vae models/loras models/controlnet models/upscale_models

# 4. Modelleri Yüksek Hızla İndir
echo "[3/5] Flux.1 Dev ve Gerekli Modeller İndiriliyor (Bu aşama 3-5 dk sürebilir)..."

# A. FLUX.1 Dev FP8 Checkpoint (Tek parça FP8 veya Unet)
huggingface-cli download Comfy-Org/flux1-dev flux1-dev-fp8.safetensors --local-dir models/checkpoints/ --local-dir-use-symlinks False &

# B. Text Encoders (CLIP-L ve T5-XXL FP8)
huggingface-cli download comfyanonymous/flux_text_encoders clip_l.safetensors t5xxl_fp8_e4m3fn.safetensors --local-dir models/clip/ --local-dir-use-symlinks False &

# C. VAE (Flux AE)
huggingface-cli download black-forest-labs/FLUX.1-dev ae.safetensors --local-dir models/vae/ --local-dir-use-symlinks False &

# D. 4x-UltraSharp Upscale Modeli
huggingface-cli download lokcx/4x-Ultrasharp 4x-UltraSharp.pth --local-dir models/upscale_models/ --local-dir-use-symlinks False &

# E. InstantX FLUX ControlNet Union Pro (Canny, Depth, Pose tek modelde)
huggingface-cli download InstantX/FLUX.1-dev-Controlnet-Union diffusion_pytorch_model.safetensors --local-dir models/controlnet/ --local-dir-use-symlinks False &

wait

# ControlNet dosyasını anlaşılır isimlendir
if [ -f "models/controlnet/diffusion_pytorch_model.safetensors" ]; then
    mv models/controlnet/diffusion_pytorch_model.safetensors models/controlnet/flux_controlnet_union_pro.safetensors
fi

# 5. Kendi GitHub Workflow'larını Otomatik İçe Aktar
echo "[4/5] Kişisel workflow'lar çekiliyor..."
mkdir -p user/default/workflows
cd user/default/workflows
git clone --depth=1 https://github.com/MucahitBilgin35/comfyui-workflows.git my_repo 2>/dev/null || (cd my_repo && git pull)
cp -r my_repo/*.json . 2>/dev/null || true
rm -rf my_repo

# 6. ComfyUI'yi Başlat
cd $COMFY_DIR
echo "======================================================"
echo "   KURULUM BAŞARIYLA TAMAMLANDI! COMFYUI AÇILIYOR...   "
echo "======================================================"
python main.py --listen 0.0.0.0 --port 8188 --fast
