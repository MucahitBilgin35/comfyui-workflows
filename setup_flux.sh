#!/bin/bash
set -e

COMFY_DIR="/workspace/ComfyUI"

echo "======================================================"
echo "   COMFYUI + FLUX DEV TAM PAKET (HER ŞEY DAHİL) KURULUM"
echo "======================================================"

mkdir -p /workspace
apt-get update -qq && apt-get install -y -qq git git-lfs aria2 tmux ffmpeg libgl1 libglib2.0-0 > /dev/null 2>&1 || true

# 1. ComfyUI Kurulumu
if [ ! -d "$COMFY_DIR" ]; then
    echo "[1/4] ComfyUI kuruluyor..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
    cd "$COMFY_DIR"
    pip install -q --break-system-packages -r requirements.txt || pip install -q -r requirements.txt
else
    cd "$COMFY_DIR"
fi

# 2. Custom Node'lar (Tüm İleri Seviye Modüller Dahil)
echo "[2/4] Custom Node'lar kuruluyor..."
mkdir -p custom_nodes && cd custom_nodes
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
    pip install -q --break-system-packages -r "$req" 2>/dev/null || pip install -q -r "$req" 2>/dev/null || true
done

# 3. Model Dizinleri
cd "$COMFY_DIR"
mkdir -p models/{checkpoints,clip,clip_vision,vae,loras,controlnet,upscale_models,ipadapter}

echo "[3/4] Tüm Modeller 16 Kanallı İndiriliyor..."

# A. CLIP & Text Encoders (Public)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" -d models/clip -o t5xxl_fp8_e4m3fn.safetensors
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" -d models/clip -o clip_l.safetensors

# B. VAE (Public Mirror)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/fffiloni/flux-dev-vae-mirror/resolve/main/ae.safetensors" -d models/vae -o ae.safetensors

# C. Upscale Modeli (4x-UltraSharp)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" -d models/upscale_models -o 4x-UltraSharp.pth

# D. ControlNet Union Pro (Canny, Depth, Pose tek modelde)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/InstantX/FLUX.1-dev-Controlnet-Union/resolve/main/diffusion_pytorch_model.safetensors" -d models/controlnet -o flux-dev-controlnet-union.safetensors

# E. Realism LoRA (Flux için Cilt ve Fotoğrafçılık LoRA'sı)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors" -d models/loras -o flux_realism.safetensors

# F. IP-Adapter & CLIP Vision (Görsel Referans / Karakter Sabitleme)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" -d models/clip_vision -o sigclip_vision_patch14_384.safetensors
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/XLabs-AI/flux-ip-adapter/resolve/main/flux-ip-adapter.safetensors" -d models/xlabs/ipadapters -o flux-ip-adapter.safetensors 2>/dev/null || aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/XLabs-AI/flux-ip-adapter/resolve/main/flux-ip-adapter.safetensors" -d models/ipadapter -o flux-ip-adapter.safetensors

# G. FLUX.1 Dev FP8 Checkpoint (Public Mirror)
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors" -d models/checkpoints -o flux1-dev-fp8.safetensors

# 4. Kişisel Workflow'ları Senkronize Et
mkdir -p user/default/workflows
cd user/default/workflows
TEMP_REPO=$(mktemp -d)
git clone --depth=1 https://github.com/MucahitBilgin35/comfyui-workflows.git "$TEMP_REPO" 2>/dev/null || true
cp -r "$TEMP_REPO"/*.json . 2>/dev/null || true
rm -rf "$TEMP_REPO"

# 5. ComfyUI'yi Başlat
cd "$COMFY_DIR"
echo "[4/4] ComfyUI Başlatılıyor..."
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui "cd $COMFY_DIR && python main.py --listen 0.0.0.0 --port 8188 --fast"

echo "======================================================"
echo "   ✅ HER ŞEY HAZIR! (FLUX DEV + REALISM + IP-ADAPTER + CONTROLNET)"
echo "   ComfyUI arka planda çalışıyor.                    "
echo "   Logları görmek için: tmux attach -t comfyui       "
echo "======================================================"
