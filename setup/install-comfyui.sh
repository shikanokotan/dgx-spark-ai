#!/usr/bin/env bash
#
# install-comfyui.sh — install ComfyUI on a DGX Spark (GB10, ARM64, sm_121).
# Run this ON the Spark. Idempotent-ish; safe to re-run.
#
# Verified on: Ubuntu 24.04, CUDA 13.0, Python 3.12, torch 2.12.0+cu130 (aarch64).
#
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
VENV_DIR="${VENV_DIR:-$HOME/comfyui-env}"

echo "[1/4] Sanity checks"
python3 --version
nvcc --version | tail -1
nvidia-smi --query-gpu=name --format=csv,noheader

echo "[2/4] Python venv at $VENV_DIR"
[ -d "$VENV_DIR" ] || python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip -q

echo "[3/4] PyTorch (CUDA 13.0 / Blackwell aarch64 wheels) + ComfyUI"
# The stock cu130 index ships aarch64 Blackwell wheels — no special fork needed.
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130
if [ ! -d "$COMFY_DIR" ]; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
fi
pip install -r "$COMFY_DIR/requirements.txt"

echo "[4/4] Verify GPU is visible to torch"
python - <<'PY'
import torch
assert torch.cuda.is_available(), "CUDA not available to torch!"
print("torch", torch.__version__, "| cuda", torch.version.cuda, "| device", torch.cuda.get_device_name(0))
PY

mkdir -p "$COMFY_DIR"/models/{diffusion_models,text_encoders,vae,loras}
echo "Done. Next: setup/download-models.sh, then server/comfyui-start.sh"
