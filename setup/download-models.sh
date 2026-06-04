#!/usr/bin/env bash
#
# download-models.sh — fetch Qwen-Image 2512 + anime LoRAs into ComfyUI.
# Run this ON the Spark, after install-comfyui.sh.
#
# Disk needed: ~72 GB (FP8 20.4 + BF16 40.8 + encoder 9.4 + VAE 0.25 + 2 LoRAs ~1.8).
# Skip BF16 with: SKIP_BF16=1 ./download-models.sh   (saves 40 GB)
#
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
M="$COMFY_DIR/models"
QHF="https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files"
mkdir -p "$M"/{diffusion_models,text_encoders,vae,loras}

dl() { # dl <url> <dest>
  if [ -s "$2" ]; then echo "  exists, skip: $(basename "$2")"; else
    echo "  downloading: $(basename "$2")"; wget -q -O "$2" "$1"; fi
}

echo "[1/4] Qwen-Image 2512 diffusion model (FP8, 20.4 GB — daily driver)"
dl "$QHF/diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors" \
   "$M/diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors"

if [ "${SKIP_BF16:-0}" != "1" ]; then
  echo "[2/4] Qwen-Image 2512 diffusion model (BF16, 40.8 GB — max quality)"
  dl "$QHF/diffusion_models/qwen_image_2512_bf16.safetensors" \
     "$M/diffusion_models/qwen_image_2512_bf16.safetensors"
else echo "[2/4] BF16 skipped (SKIP_BF16=1)"; fi

echo "[3/4] Text encoder (Qwen2.5-VL 7B) + VAE"
dl "$QHF/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
   "$M/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
dl "$QHF/vae/qwen_image_vae.safetensors" "$M/vae/qwen_image_vae.safetensors"

echo "[4/4] Anime LoRAs (text-to-image, verified on 2512)"
# prithivMLmods — trigger: "Qwen Anime"  (strong anime/illustration look)
dl "https://huggingface.co/prithivMLmods/Qwen-Image-Anime-LoRA/resolve/main/qwen-anime.safetensors" \
   "$M/loras/qwen_anime_prithiv.safetensors"
# alfredplpl — trigger: "Japanese modern anime style"
dl "https://huggingface.co/alfredplpl/qwen-image-modern-anime-lora/resolve/main/diffusers.safetensors" \
   "$M/loras/qwen_modern_anime_alfredplpl.safetensors"

echo "Done. Files:"
ls -la "$M"/diffusion_models "$M"/text_encoders "$M"/vae "$M"/loras
