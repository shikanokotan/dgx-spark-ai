#!/usr/bin/env bash
#
# nemoclaw-set-model.sh — switch the model NemoClaw uses, the right way.
# Run ON the Spark.   Usage:  ./nemoclaw-set-model.sh <ollama-model> [sandbox]
#   e.g.  ./nemoclaw-set-model.sh gpt-oss:120b
#         ./nemoclaw-set-model.sh qwen3.6:35b
#
# Why --no-verify: the CLI's verify step connects to
# `host.openshell.internal:11435` from the HOST, but that docker-internal name
# only resolves INSIDE the sandbox, so verify always errors on the host even
# though the runtime path is fine (NVIDIA NemoClaw issue #1786). We skip verify
# and confirm with `status` instead. Optionally pre-warm big models first.
#
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

MODEL="${1:?usage: nemoclaw-set-model.sh <ollama-model> [sandbox]}"
SANDBOX="${2:-spark-assistant}"

echo "[1/3] Pre-warming $MODEL in Ollama (first load of large models is slow)"
curl -s http://127.0.0.1:11434/api/generate \
     -d "{\"model\":\"$MODEL\",\"prompt\":\"hi\",\"stream\":false,\"keep_alive\":\"30m\"}" \
     -o /dev/null -w "  load http=%{http_code} time=%{time_total}s\n" || true

echo "[2/3] Setting NemoClaw inference route to $MODEL"
nemoclaw inference set --model "$MODEL" --provider ollama-local --sandbox "$SANDBOX" --no-verify

echo "[3/3] Status"
nemoclaw "$SANDBOX" status | head -8
