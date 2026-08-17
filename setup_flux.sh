#!/bin/bash
set -e

# Hugging Face Token (Flux Dev için)
# Eğer çalıştırma sırasında HF_TOKEN tanımlanmamışsa buradaki değeri kullanır
HF_TOKEN="${HF_TOKEN:-hf_SENIN_TOKENIN}"
COMFY_DIR="/workspace/ComfyUI"

echo "======================================================"
echo "   COMFYUI + FLUX DEV TEK HAMLEDE KURULUM BAŞLADI     "
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

# 2. Custom Node'lar
echo "[2/4] Custom Node'lar kuruluyor..."
mkdir -p custom_nodes && cd custom_nodes
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git 2>/dev/null || true &
git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git 2>/dev/null || true &
git clone --depth=1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git 2>/dev/null || true &
git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git 2>/dev/null || true &
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git 2>/dev/null || true &
git clone --depth=1 https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git 2>/dev/null || true &
git clone --depth=1 https://github.com/cubiq/ComfyUI_essentials.git 2>/dev/null || true &
wait

for req in */requirements.txt; do
    pip install -q --break-system-packages -r "$req" 2>/dev/null || pip install -q -r "$req" 2>/dev/null || true
done

# 3. Modeller (aria2c 16x)
echo "[3/4] Modeller 16 kanallı yüksek hızla indiriliyor..."
cd "$COMFY_DIR"
mkdir -p models/{checkpoints,clip,vae,loras,controlnet,upscale_models}

aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" -d models/clip -o t5xxl_fp8_e4m3fn.safetensors
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" -d models/clip -o clip_l.safetensors
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" -d models/vae -o ae.safetensors
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" -d models/upscale_models -o 4x-UltraSharp.pth
aria2c -c -x 16 -s 16 -k 1M "https://huggingface.co/InstantX/FLUX.1-dev-Controlnet-Union/resolve/main/diffusion_pytorch_model.safetensors" -d models/controlnet -o flux-dev-controlnet-union.safetensors
aria2c -c -x 16 -s 16 -k 1M --header="Authorization: Bearer $HF_TOKEN" "https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors" -d models/checkpoints -o flux1-dev-fp8.safetensors

# 4. Başlat
echo "[4/4] ComfyUI Başlatılıyor..."
tmux kill-session -t comfyui 2>/dev/null || true
tmux new-session -d -s comfyui "cd $COMFY_DIR && python main.py --listen 0.0.0.0 --port 8188 --fast"

echo "======================================================"
echo "   ✅ KURULUM TAMAMLANDI!                            "
echo "   ComfyUI arka planda çalışıyor.                    "
echo "   Logları görmek için: tmux attach -t comfyui       "
echo "======================================================"
