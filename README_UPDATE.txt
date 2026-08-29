COMFYUI / CLORE — FINAL STABLE SCRIPT SET

NORMAL GOLDEN BUILD
1) Run setup_everything.sh once on a clean Clore machine.
2) Test ComfyUI and your core workflows.
3) If you want the optional toolbox too, run setup_fluxDev1Extras.sh once.
4) Test again. If stable, make your Hugging Face Golden Snapshot.

WHAT WAS ADDED TO THE STABLE TOOLBOX
- ComfyUI-Impact-Subpack: UltralyticsDetectorProvider / FaceDetailer support.
- ComfyUI-Lora-Manager: previews, trigger words, notes and recipes.
- ComfyUI-Crystools: VRAM/RAM/time monitoring and image/JSON comparison.

WHAT LIVES ONLY IN setup_fluxDev1Extras.sh
- ComfyUI-Florence2 (useful phrase grounding / region selection; kept out of stable base because of current Transformers compatibility churn).
- ComfyUI-RMBG (advanced background removal / segmentation).
- SeedVR2 7B FP8 (large quality comparison option).
- Official BFL Canny/Depth LoRAs are wired in but DISABLED by default because they are gated/licensed. Set INSTALL_BFL_CONTROL_LORAS=1 only after accepting access on Hugging Face and supplying HF_TOKEN.

NOT INCLUDED ON PURPOSE
- FLUX Kontext / Qwen Edit / FLUX Klein / Krea as default downloads: large alternative model families, better added when their learning phase starts.
- TeaCache / WaveSpeed in the stable learning environment: speed optimizers can change behavior and currently have compatibility churn.
- WAS Node Suite: archived.
- IPAdapter Plus as the primary FLUX path: maintenance-only; this stack uses x-flux for FLUX IP-Adapter.

SPEED
- Hugging Face downloads use hf_xet High Performance automatically on ~64 GB+ RAM machines.
- Xet adaptive concurrency is left enabled because Hugging Face recommends it for saturating most network paths.
- aria2 (16 connections) is the fallback.

COMFYUI START
All setup profiles start ComfyUI automatically. You do NOT need to type the long tmux command afterward.
To view logs: tmux attach -t comfyui
