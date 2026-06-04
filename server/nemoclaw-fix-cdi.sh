#!/usr/bin/env bash
#
# nemoclaw-fix-cdi.sh — fix the NemoClaw install hang where the NVIDIA CDI
# device-spec generation never completes.
#
# Root cause (seen on this DGX Spark): the systemd job queue is jammed behind
# `plymouth-quit-wait.service` (boot splash that never exits on a headless box),
# so `nvidia-cdi-refresh.service` is stuck "waiting" and the installer's
# `systemctl --now` blocks forever. We clear plymouth and generate the spec
# directly (NemoClaw's own documented fallback).
#
# Run ON the Spark. Needs sudo.  After this, re-run the NemoClaw installer.
#
set -euo pipefail

echo "[1/3] Clearing plymouth job-queue jam"
sudo systemctl stop plymouth-quit-wait.service 2>/dev/null || true
sudo systemctl stop plymouth-quit.service      2>/dev/null || true
sudo systemctl stop plymouth-start.service     2>/dev/null || true

echo "[2/3] Generating CDI spec directly"
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

echo "[3/3] Verifying"
ls -la /etc/cdi/nvidia.yaml
nvidia-ctk cdi list | head -6
echo "OK — CDI spec present. Re-run: curl -fsSL https://www.nvidia.com/nemoclaw.sh | NEMOCLAW_INSTALL_TAG=v0.0.55 bash"
