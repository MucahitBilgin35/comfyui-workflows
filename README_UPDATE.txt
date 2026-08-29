GITHUB UPDATE - 2026-08-29

Upload these files to the repository root:
  _comfy_common.sh
  setup_full.sh
  setup_weekend.sh
  setup_fluxDev1Extras.sh
  setup_everything.sh   (new, recommended one-click option)

Recommended new-machine command:

  apt-get update -qq && apt-get install -y -qq curl ca-certificates
  curl -fL --retry 5 https://raw.githubusercontent.com/MucahitBilgin35/comfyui-workflows/main/setup_everything.sh -o setup_everything.sh
  chmod +x setup_everything.sh
  bash setup_everything.sh

The wrapper automatically fetches _comfy_common.sh.

Profiles:
  setup_full.sh            = core + LoRA + ControlNet + identity essentials
  setup_weekend.sh         = full richer toolbox
  setup_fluxDev1Extras.sh  = advanced extras for an existing base
  setup_everything.sh      = recommended one-click complete learning toolbox

Speed:
  - Hugging Face Xet high-performance mode auto-enables on 60 GB+ RAM.
  - HF download has aria2 16-connection fallback.
  - Git clones are shallow/filtered.
  - pip uses binary packages when possible.

Removed from default install:
  - WAS Node Suite (repository archived in 2025)
  - ComfyUI_IPAdapter_plus (maintenance-only; FLUX stack uses x-flux)
  - old ComfyUI-SUPIR wrapper (SUPIR is in ComfyUI core)

FLUX.1 Fill Dev is gated/licensed and is skipped by default. After accepting its license,
set ACCEPT_FLUX_DEV_LICENSE=1 and HF_TOKEN before running the rich/everything profile.
