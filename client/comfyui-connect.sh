#!/usr/bin/env bash
#
# comfyui-connect.sh — make sure ComfyUI is running on the DGX Spark, open an
# SSH tunnel to it, and launch the UI in the browser.
#
# Usage:
#   ./comfyui-connect.sh            ensure running + tunnel + browser (Ctrl-C closes tunnel)
#   ./comfyui-connect.sh --check    self-test: tunnel + verify UI reachable, then exit
#   ./comfyui-connect.sh --no-open  tunnel only, print the URL (no browser)
#   ./comfyui-connect.sh stop       kill any tunnel this script opened
#
# Config (override via env):
#   CU_HOST=dgx.zrh.arts.moe   CU_PORT=8188
#
set -euo pipefail

CU_HOST="${CU_HOST:-dgx.zrh.arts.moe}"
CU_PORT="${CU_PORT:-8188}"
URL="http://127.0.0.1:${CU_PORT}/"

c_info=$'\033[36m'; c_ok=$'\033[32m'; c_err=$'\033[31m'; c_off=$'\033[0m'
log(){ printf '%s[comfyui]%s %s\n' "$c_info" "$c_off" "$*" >&2; }
ok(){  printf '%s[comfyui]%s %s\n' "$c_ok"   "$c_off" "$*" >&2; }
err(){ printf '%s[comfyui]%s %s\n' "$c_err"  "$c_off" "$*" >&2; }

MODE="open"
case "${1:-}" in
  --check) MODE="check" ;; --no-open) MODE="noopen" ;; stop) MODE="stop" ;;
  "") MODE="open" ;; *) err "Unknown argument: $1"; exit 2 ;;
esac

if [ "$MODE" = "stop" ]; then
  pids="$(pgrep -f "ssh.*-L ${CU_PORT}:127.0.0.1:${CU_PORT}.*$CU_HOST" || true)"
  if [ -n "$pids" ]; then echo "$pids" | xargs kill 2>/dev/null || true; ok "Closed tunnel(s): $pids"
  else log "No tunnel found for $CU_HOST:$CU_PORT."; fi
  exit 0
fi

# 1. make sure ComfyUI is running on the box (idempotent launcher)
log "Ensuring ComfyUI is running on $CU_HOST ..."
ssh -o ConnectTimeout=15 "$CU_HOST" '$HOME/comfyui-start.sh' >/dev/null 2>&1 || \
  err "Could not run remote launcher (it may already be up); continuing."

# 2. open the tunnel (reuse if present)
TUN=""
if lsof -nP -iTCP:"$CU_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  log "Local port $CU_PORT already listening — reusing existing tunnel."
else
  log "Opening SSH tunnel  $CU_PORT -> 127.0.0.1:$CU_PORT  on $CU_HOST ..."
  ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      -L "$CU_PORT:127.0.0.1:$CU_PORT" "$CU_HOST" &
  TUN=$!
  trap '[ -n "$TUN" ] && kill "$TUN" 2>/dev/null; log "Tunnel closed."' EXIT INT TERM
fi

# 3. wait for the UI to answer (ComfyUI may still be loading after a fresh start)
log "Waiting for ComfyUI to respond ..."
up=0
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL" || echo 000)"
  [ "$code" = "200" ] && { up=1; break; }
  sleep 1
done
[ "$up" = "1" ] && ok "ComfyUI reachable through tunnel (HTTP 200)." || { err "ComfyUI did not respond on $URL"; exit 1; }

if [ "$MODE" = "check" ]; then ok "Self-test passed."; exit 0; fi

printf '\n%s\n\n' "$URL"
if [ "$MODE" = "open" ]; then
  if command -v open >/dev/null 2>&1; then open "$URL"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
  else log "Open the URL above in your browser."; fi
  ok "Browser launched."
fi

if [ -n "$TUN" ]; then
  log "Tunnel running. Press Ctrl-C to close it."
  wait "$TUN"
else
  log "Reusing a pre-existing tunnel; not holding it open. Run './comfyui-connect.sh stop' to close it."
fi
