# Admin Guide

How the stack is built, how to rebuild it, and every gotcha hit along the way.

- **Host:** `dgx.zrh.arts.moe`, user `arts`
- **Platform:** DGX Spark, GB10 (Grace-Blackwell), 119 GiB unified memory, 20-core ARM64 (`aarch64`, compute `sm_121`), Ubuntu 24.04, CUDA 13.0, Docker 29.x

---

## 1. Architecture

```
  Your Mac                                  DGX Spark (dgx.zrh.arts.moe)
  ────────                                  ────────────────────────────
  ComfyUI.command ─┐                        ┌─ ComfyUI  (venv, 127.0.0.1:8188)
  comfyui-connect ─┼── ssh -L 8188 ────────►┤    └─ Qwen-Image 2512 + LoRAs (GPU)
                   │                         │
  nemoclaw-connect ┼── ssh -L 18789 ────────►├─ NemoClaw dashboard (127.0.0.1:18789)
                   │                         │    └─ OpenShell sandbox "spark-assistant"
                   │                         │         └─ OpenClaw agent
                   │                         │              │ host.openshell.internal:11435
                   │                         │              ▼
                   │                         └─ Ollama (systemd, 127.0.0.1:11434
                   │                              auth proxy :11435)
                   │                              └─ qwen3.6:35b, gpt-oss:120b (GPU)
```

Everything binds to **localhost** on the Spark. ComfyUI has **no authentication**,
so it must never be bound to `0.0.0.0`; reach it only via the SSH tunnel.
NemoClaw's dashboard has a token. Both LLM and image models share the 119 GiB
unified memory (used as VRAM).

---

## 2. Rebuild from scratch

### 2a. NemoClaw (LLM chat/agents)
```bash
# On the Spark. Installs Node, OpenShell, NemoClaw CLI, runs the onboard wizard.
curl -fsSL https://www.nvidia.com/nemoclaw.sh | NEMOCLAW_INSTALL_TAG=v0.0.55 bash
```
Onboard wizard answers used: accept license → inference **8) Install Ollama** →
model **qwen3.6:35b** → sandbox name **spark-assistant** → skip Brave/messaging →
profile **creator (50%)** → policy **Balanced** (defaults).

> **Gotcha — install hangs at "Generating … CDI device spec".** The systemd job
> queue was jammed behind `plymouth-quit-wait.service` (headless boot splash),
> so `nvidia-cdi-refresh.service` never ran and the installer's `systemctl --now`
> blocked forever. Fix and re-run:
> ```bash
> bash server/nemoclaw-fix-cdi.sh     # stops plymouth, runs nvidia-ctk cdi generate
> ```

Add the second model and switch:
```bash
ollama pull gpt-oss:120b
bash server/nemoclaw-set-model.sh gpt-oss:120b   # or qwen3.6:35b
```
> **Gotcha — `nemoclaw inference set` fails verification.** The verify connects to
> `host.openshell.internal:11435` from the host, but that docker-internal name
> only resolves *inside* the sandbox (→`172.18.0.1`). Always pass `--no-verify`
> (the helper script does) and confirm with `nemoclaw spark-assistant status`.
> Ref: NVIDIA NemoClaw issue #1786.

### 2b. ComfyUI (image generation)
```bash
# On the Spark.
bash setup/install-comfyui.sh      # venv ~/comfyui-env + torch cu130 + ComfyUI ~/ComfyUI
bash setup/download-models.sh      # Qwen-Image 2512 (FP8+BF16) + encoder + VAE + 2 anime LoRAs
cp server/workflows/Qwen2512-Anime-LoRA.json ~/ComfyUI/user/default/workflows/
bash server/comfyui-start.sh       # launch in tmux session 'comfy' on 127.0.0.1:8188
```
> **Gotcha — sm_121 / ARM64 wheels.** Standard ComfyUI/PyTorch wheels historically
> didn't cover `sm_121`. As of torch **2.12.0+cu130** the stock
> `download.pytorch.org/whl/cu130` index ships working aarch64 Blackwell wheels —
> no fork needed. Verify: `python -c "import torch; print(torch.cuda.get_device_name(0))"`
> → `NVIDIA GB10`. (If a future wheel regresses, fall back to an NVIDIA PyTorch
> container or the SparkyUI docker setup.)

Auto-start on boot (no sudo) is wired by `comfyui-start.sh` + a user crontab entry:
```
@reboot $HOME/comfyui-start.sh >> $HOME/comfyui-cron.log 2>&1
```

### 2c. Verify end-to-end
```bash
# On the Spark, with ComfyUI running:
~/comfyui-env/bin/python server/test/qwen_test.py                 # base 2512
~/comfyui-env/bin/python server/test/qwen_lora_test.py \
    qwen_anime_prithiv.safetensors "Qwen Anime" lora_check        # with LoRA
```
A healthy LoRA run logs `… patches attached` (>0) and **zero** `lora key not loaded`
warnings in `~/comfyui.log`.

---

## 3. Models & files on the Spark
```
~/ComfyUI/models/
  diffusion_models/ qwen_image_2512_fp8_e4m3fn.safetensors   (20.4 GB, default)
                    qwen_image_2512_bf16.safetensors         (40.8 GB, max quality)
  text_encoders/    qwen_2.5_vl_7b_fp8_scaled.safetensors    (9.4 GB)
  vae/              qwen_image_vae.safetensors               (0.25 GB)
  loras/            qwen_anime_prithiv.safetensors           (trigger "Qwen Anime")
                    qwen_modern_anime_alfredplpl.safetensors (trigger "Japanese modern anime style")
~/ComfyUI/user/default/workflows/Qwen2512-Anime-LoRA.json
```
Ollama models: `qwen3.6:35b`, `gpt-oss:120b` (`ollama list`).

### Adding more models / LoRAs
- ComfyUI rescans its `models/` folders by directory mtime, but to be safe
  **restart ComfyUI** after dropping new files so node dropdowns refresh.
- New LoRA → `~/ComfyUI/models/loras/`. Civitai needs an API token for downloads;
  HuggingFace files can be `wget`'d directly (see `download-models.sh` for the pattern).
- Regenerate the workflow template after changing node defaults:
  `~/comfyui-env/bin/python server/build_workflow.py`.

> **When authoring ComfyUI UI/litegraph JSON for this build:** `CLIPLoader` has only
> `[clip_name, type]` widgets (no `device`); `KSampler` `widgets_values` includes
> `control_after_generate` right after `seed` (7 values total). Mismatched widget
> counts load misaligned. Validate node widgets via `GET /object_info/<NodeType>`.

---

## 4. Operations

| Task | Command (on the Spark) |
|---|---|
| ComfyUI status | `tmux has-session -t comfy && echo up` |
| ComfyUI logs | `tail -f ~/comfyui.log` |
| Restart ComfyUI | `tmux kill-session -t comfy; ~/comfyui-start.sh` |
| NemoClaw status | `nemoclaw spark-assistant status` |
| NemoClaw logs | `nemoclaw spark-assistant logs --follow` |
| Switch LLM | `bash server/nemoclaw-set-model.sh <model>` |
| List Ollama models | `ollama list` / `ollama ps` (loaded) |
| GPU/mem | `nvidia-smi` (note: unified memory may show `N/A` for used) |

PATHs: `nemoclaw` → `~/.local/bin`; `ollama` → `/usr/local/bin`; ComfyUI venv →
`~/comfyui-env`. New shells may need `source ~/.bashrc`.

---

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| NemoClaw install hangs at CDI spec | plymouth job-queue jam → `bash server/nemoclaw-fix-cdi.sh`, re-run installer |
| `nemoclaw inference set` verify error to `host.openshell.internal:11435` | host can't resolve the docker name → use `--no-verify` (issue #1786); the path is fine inside the sandbox |
| `gpt-oss:120b` first reply very slow | 65 GB cold-load; pre-warm via `nemoclaw-set-model.sh` (does it) or `ollama run gpt-oss:120b ""` |
| ComfyUI: `torch.cuda.is_available()` False | wrong wheel — reinstall with `--index-url https://download.pytorch.org/whl/cu130` |
| LoRA has no visible effect | check `~/comfyui.log` for `lora key not loaded`; if many, the LoRA isn't format-compatible with Qwen-Image |
| New model/LoRA missing in dropdown | restart ComfyUI (`tmux kill-session -t comfy; ~/comfyui-start.sh`) |
| Can't reach UI through tunnel | ComfyUI binds `127.0.0.1` only; ensure tunnel up (`comfyui-connect.sh --check`) — do **not** bind `0.0.0.0` (no auth) |
| SSH "connection refused" briefly | transient sshd/network blip seen once; the box was not rebooting — just retry |

---

## 6. Security notes
- All services bind **localhost** on the Spark; access is via SSH tunnel only.
- **ComfyUI has no auth** — never expose port 8188 to the LAN/internet.
- NemoClaw dashboard uses a rotating token (`nemoclaw spark-assistant dashboard-url`).
- Local inference means **no data leaves the box** — no cloud API keys configured.
- Sudo was needed only for: CDI spec generation and the Ollama systemd install.
