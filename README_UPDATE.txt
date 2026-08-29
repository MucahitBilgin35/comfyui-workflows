COMFYUI CLORE STABLE v2.1 — FULL GOLDEN + SAFE PRELOAD

Recommended deployment architecture:

1) Create ONE clean FULL Golden snapshot with setup_full.sh.
2) Store that compressed snapshot privately on Hugging Face.
3) On a new Clore machine restore it with restore_full_snapshot.sh and begin work immediately.
4) While ComfyUI is running, optionally download later-phase model files using preload_weekend.sh --background or preload_extras.sh --background.
5) After the current work/render is finished, run setup_weekend.sh or setup_fluxDev1Extras.sh once to install missing nodes/dependencies and restart ComfyUI.

Key v2.1 changes:
- Existing restored ComfyUI base is preserved; setup_weekend no longer needlessly reinstalls base/Torch unless FORCE_BASE_REFRESH=1.
- Existing model files are skipped.
- Existing custom nodes are kept pinned unless UPDATE_NODES=1.
- Node requirements use per-commit markers, avoiding repeated pip installs after a v2.1 Golden snapshot.
- Preload mode never clones nodes, changes the ComfyUI venv, or restarts ComfyUI.
- Partial downloads use .part names and are moved into canonical model paths only after completion.
- Hugging Face/Xet transfer tooling lives in /workspace/.comfy-transfer-venv, separate from ComfyUI's venv.
- FULL -> Extras can be done directly: preload_extras.sh downloads Weekend delta + Extras models; setup_fluxDev1Extras.sh activates advanced/extras nodes later.

Main scripts:
- setup_full.sh                  : build the clean FULL stable base
- setup_weekend.sh               : activate rich/advanced stable layer
- setup_everything.sh            : fresh one-click rich stable install
- setup_fluxDev1Extras.sh        : activate optional extras layer
- preload_weekend.sh             : model-only safe background Weekend preload
- preload_extras.sh              : model-only safe background Weekend+Extras preload
- backup_snapshot_to_hf.sh       : compress/upload CURRENT /workspace/ComfyUI
- restore_full_snapshot.sh       : restore FULL Golden and auto-start ComfyUI
- start_comfyui.sh               : start/restart ComfyUI safely
- _comfy_common.sh               : shared implementation
- QUICK_TUTORIAL.md              : short Turkish tutorial
