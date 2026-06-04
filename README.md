# DGX Spark AI Stack

Local, private AI on the **DGX Spark** (`dgx.zrh.arts.moe`) — open-source LLMs and
anime-capable image generation, reachable from a laptop over an SSH tunnel.

| Capability | Stack | Models |
|---|---|---|
| **Chat / agents** | [NemoClaw](https://docs.nvidia.com/nemoclaw/) + OpenShell sandbox + Ollama | `qwen3.6:35b` (default), `gpt-oss:120b` |
| **Image generation** | [ComfyUI](https://github.com/comfyanonymous/ComfyUI) | Qwen-Image 2512 (FP8 + BF16) + anime LoRAs |

Everything runs **on-device** (no cloud API keys) and is bound to `localhost`,
reached only through an SSH tunnel.

## Hardware / platform
- DGX Spark, **GB10** Grace-Blackwell, **119 GiB unified memory**, 20-core ARM64 (`aarch64`, `sm_121`)
- Ubuntu 24.04, CUDA 13.0, Docker 29.x

## Repo layout
```
client/                  run on your Mac/laptop
  ComfyUI.command        double-click → tunnel + open ComfyUI in browser
  comfyui-connect.sh     ComfyUI tunnel (port 8188)
  nemoclaw-connect.sh    NemoClaw dashboard tunnel (port 18789, fresh token)
server/                  run on the Spark
  comfyui-start.sh       start ComfyUI in a detached tmux session
  nemoclaw-fix-cdi.sh    fix the CDI/plymouth install hang
  nemoclaw-set-model.sh  switch NemoClaw's model (handles the --no-verify quirk)
  build_workflow.py      regenerate the ComfyUI workflow template
  workflows/             ComfyUI workflow template(s)
  test/                  headless generation tests (API)
setup/                   run on the Spark, once
  install-comfyui.sh     venv + torch (cu130/aarch64) + ComfyUI
  download-models.sh     Qwen-Image 2512 + encoders + VAE + anime LoRAs
docs/samples/            example outputs
```

## Start here
- **Just want to use it?** → [USERGUIDE.md](USERGUIDE.md)
- **Installing / maintaining / rebuilding?** → [ADMINGUIDE.md](ADMINGUIDE.md)
