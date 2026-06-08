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
# Choosing your account: if you don't preset one, the script shows a menu and
# asks which Spark account is yours. To skip the menu, set DGX_USER (your name)
# or CU_HOST (full user@host). Config via env or a file — see dgx.conf.example:
#   DGX_USER=lzr   DGX_HOST=dgx.zrh.arts.moe   DGX_USERS="arts lzr yue yuki"
#   CU_PORT=8188   CU_OWNER=arts   CU_HOST=you@host  (advanced full override)
#
# Multi-user note: every local account on the Spark shares ONE ComfyUI instance
# (it binds 127.0.0.1; your SSH tunnel forwards to it regardless of which account
# you log in as).
#
set -euo pipefail

# Optional per-user config so you don't have to export env every time.
# Env vars set on the command line still win (config uses `: "${VAR:=...}"`).
for _cfg in "${DGX_CONF:-}" "$HOME/.config/dgx-spark.conf" "$(dirname "$0")/dgx.conf"; do
  [ -n "$_cfg" ] && [ -f "$_cfg" ] && . "$_cfg"
done

DGX_HOST="${DGX_HOST:-dgx.zrh.arts.moe}"   # base host (no username)
CU_PORT="${CU_PORT:-8188}"
CU_OWNER="${CU_OWNER:-arts}"   # account that owns the shared ComfyUI service
URL="http://127.0.0.1:${CU_PORT}/"

c_info=$'\033[36m'; c_ok=$'\033[32m'; c_err=$'\033[31m'; c_off=$'\033[0m'
log(){ printf '%s[comfyui]%s %s\n' "$c_info" "$c_off" "$*" >&2; }
ok(){  printf '%s[comfyui]%s %s\n' "$c_ok"   "$c_off" "$*" >&2; }
err(){ printf '%s[comfyui]%s %s\n' "$c_err"  "$c_off" "$*" >&2; }

# Pick the Spark account to log in as: $DGX_USER if preset, else an interactive
# menu (choices from $DGX_USERS). Echoes the chosen username (may be empty when
# non-interactive — then we fall back to your local username).
dgx_pick_account(){
  [ -n "${DGX_USER:-}" ] && { printf '%s' "$DGX_USER"; return; }
  { [ -t 0 ] || [ -t 1 ]; } || { printf ''; return; }   # non-interactive: no prompt
  local choices; read -r -a choices <<< "${DGX_USERS:-arts lzr yue yuki}"
  local i=1 c
  printf '%bWhich DGX Spark account is yours?%b\n' "$c_info" "$c_off" >&2
  for c in "${choices[@]}"; do printf '   %d) %s\n' "$i" "$c" >&2; i=$((i+1)); done
  printf '   %d) other (type a username)\n' "$i" >&2
  local n=""; read -r -p "Choice [1]: " n </dev/tty || true
  n="${n:-1}"
  if [ "$n" = "$i" ]; then
    local u=""; read -r -p "Spark username: " u </dev/tty || true; printf '%s' "$u"; return
  fi
  case "$n" in *[!0-9]*|'') n=1 ;; esac
  if [ "$n" -ge 1 ] && [ "$n" -le "${#choices[@]}" ]; then printf '%s' "${choices[$((n-1))]}"
  else printf '%s' "${choices[0]}"; fi
}

MODE="open"
case "${1:-}" in
  --check) MODE="check" ;; --no-open) MODE="noopen" ;; stop) MODE="stop" ;;
  "") MODE="open" ;; *) err "Unknown argument: $1"; exit 2 ;;
esac

# Resolve user@host. Explicit CU_HOST wins; otherwise pick an account (prompting
# only for the real actions, never for the lightweight 'stop').
if [ -z "${CU_HOST:-}" ]; then
  if [ "$MODE" = "stop" ]; then _u="${DGX_USER:-}"; else _u="$(dgx_pick_account)"; fi
  CU_HOST="${_u:+$_u@}$DGX_HOST"
fi

if [ "$MODE" = "stop" ]; then
  pids="$(pgrep -f "ssh.*-L ${CU_PORT}:127.0.0.1:${CU_PORT}.*$CU_HOST" || true)"
  if [ -n "$pids" ]; then echo "$pids" | xargs kill 2>/dev/null || true; ok "Closed tunnel(s): $pids"
  else log "No tunnel found for $CU_HOST:$CU_PORT."; fi
  exit 0
fi

# 1. make sure the shared ComfyUI is running on the box (idempotent, best-effort).
#    If you own it ($HOME/comfyui-start.sh exists), start it directly; otherwise
#    ask the owner's account via the sudo wrapper installed by enable-multiuser.sh.
#    Either way it's best-effort — the health check below is what actually gates us.
log "Ensuring the shared ComfyUI is running on $CU_HOST ..."
ssh -o ConnectTimeout=15 "$CU_HOST" \
  "\$HOME/comfyui-start.sh 2>/dev/null || sudo -n -u $CU_OWNER /usr/local/bin/comfyui-ensure 2>/dev/null || true" \
  >/dev/null 2>&1 || \
  err "Could not trigger the remote launcher (it may already be up); continuing."

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
[ "$up" = "1" ] && ok "ComfyUI reachable through tunnel (HTTP 200)." || {
  err "ComfyUI did not respond on $URL."
  err "The shared instance may be down — ask $CU_OWNER to start it, or (if you're in the dgx-ai group) run:"
  err "  ssh $CU_HOST 'sudo -u $CU_OWNER /usr/local/bin/comfyui-ensure'"
  exit 1
}

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
