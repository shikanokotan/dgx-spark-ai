#!/usr/bin/env bash
#
# nemoclaw-connect.sh — open an SSH tunnel to the DGX Spark NemoClaw dashboard,
# fetch a fresh authenticated (tokenized) URL, and launch it in the browser.
#
# Usage:
#   ./nemoclaw-connect.sh            open tunnel + browser, stay up (Ctrl-C to close)
#   ./nemoclaw-connect.sh --check    self-test: tunnel + verify dashboard reachable, then exit
#   ./nemoclaw-connect.sh --no-open  open tunnel but don't launch the browser (prints URL)
#   ./nemoclaw-connect.sh stop       kill any tunnel this script left on the port
#
# Choosing your account: if you don't preset one, the script shows a menu and
# asks which Spark account is yours. To skip the menu, set DGX_USER (your name)
# or NC_HOST (full user@host). Config via env or a file — see dgx.conf.example:
#   DGX_USER=lzr   DGX_HOST=dgx.zrh.arts.moe   DGX_USERS="arts lzr yue yuki"
#   NC_SANDBOX=spark-assistant   NC_OWNER=arts   NC_HOST=you@host  (full override)
#
# Multi-user note: there's ONE shared NemoClaw assistant, owned by NC_OWNER. If
# you log in as a different Spark user you don't have the `nemoclaw` CLI or the
# sandbox state, so the dashboard token is fetched on your behalf via the sudo
# wrapper from setup/enable-multiuser.sh (you must be in the dgx-ai group).
#
set -euo pipefail

# Optional per-user config (env on the command line still wins). See dgx.conf.example.
for _cfg in "${DGX_CONF:-}" "$HOME/.config/dgx-spark.conf" "$(dirname "$0")/dgx.conf"; do
  [ -n "$_cfg" ] && [ -f "$_cfg" ] && . "$_cfg"
done

DGX_HOST="${DGX_HOST:-dgx.zrh.arts.moe}"   # base host (no username)
NC_SANDBOX="${NC_SANDBOX:-spark-assistant}"
NC_OWNER="${NC_OWNER:-arts}"   # account that owns the shared NemoClaw assistant
REMOTE_PATH='export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"'

c_info=$'\033[36m'; c_ok=$'\033[32m'; c_err=$'\033[31m'; c_off=$'\033[0m'
log(){ printf '%s[nemoclaw]%s %s\n' "$c_info" "$c_off" "$*" >&2; }
ok(){  printf '%s[nemoclaw]%s %s\n' "$c_ok"   "$c_off" "$*" >&2; }
err(){ printf '%s[nemoclaw]%s %s\n' "$c_err"  "$c_off" "$*" >&2; }

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
  --check)   MODE="check" ;;
  --no-open) MODE="noopen" ;;
  stop)      MODE="stop" ;;
  "" )       MODE="open" ;;
  *) err "Unknown argument: $1"; exit 2 ;;
esac

# Resolve user@host. Explicit NC_HOST wins; otherwise pick an account (prompting
# only for the real actions, never for the lightweight 'stop').
if [ -z "${NC_HOST:-}" ]; then
  if [ "$MODE" = "stop" ]; then _u="${DGX_USER:-}"; else _u="$(dgx_pick_account)"; fi
  NC_HOST="${_u:+$_u@}$DGX_HOST"
fi

# ---- stop mode: tear down any tunnel we started ---------------------------
if [ "$MODE" = "stop" ]; then
  pids="$(pgrep -f "ssh.*-L [0-9]*:127.0.0.1:[0-9]*.*$NC_HOST" || true)"
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill 2>/dev/null || true
    ok "Closed tunnel(s): $pids"
  else
    log "No tunnel found for $NC_HOST."
  fi
  exit 0
fi

# ---- 1. fetch a fresh authenticated dashboard URL (server generates token) -
# Works whether you ARE the owner (nemoclaw on PATH → call it directly) or a
# different Spark user (no nemoclaw → go through the sudo wrapper as the owner).
log "Fetching authenticated dashboard URL from $NC_HOST ..."
REMOTE_FETCH="$REMOTE_PATH
if command -v nemoclaw >/dev/null 2>&1; then
  nemoclaw $NC_SANDBOX dashboard-url --quiet
else
  sudo -n -u $NC_OWNER /usr/local/bin/nemoclaw-dashboard-url $NC_SANDBOX
fi"
URL="$(ssh -o ConnectTimeout=15 "$NC_HOST" "$REMOTE_FETCH" 2>/dev/null \
        | tr -d '\r' | grep -E '^https?://' | head -1 || true)"

if [ -z "$URL" ]; then
  err "Could not retrieve the dashboard URL."
  err "If you ARE $NC_OWNER:   ssh $NC_HOST 'nemoclaw $NC_SANDBOX status'"
  err "If you're another user: you must be in the dgx-ai group (ask $NC_OWNER to run"
  err "  setup/enable-multiuser.sh and add you), then retry."
  exit 1
fi

# port lives in the URL (http://127.0.0.1:<port>/#token=...); default 18789
PORT="$(printf '%s' "$URL" | sed -nE 's#^https?://[^:/]+:([0-9]+).*#\1#p')"
PORT="${PORT:-18789}"
ok "Got tokenized URL (port $PORT)."

# ---- 2. open the SSH tunnel (reuse if one is already listening) -----------
TUN=""
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  log "Port $PORT already listening — reusing existing tunnel."
else
  log "Opening SSH tunnel  $PORT -> 127.0.0.1:$PORT  on $NC_HOST ..."
  ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      -L "$PORT:127.0.0.1:$PORT" "$NC_HOST" &
  TUN=$!
  trap '[ -n "$TUN" ] && kill "$TUN" 2>/dev/null; log "Tunnel closed."' EXIT INT TERM
fi

# wait until the forwarded port actually answers
for _ in $(seq 1 30); do
  nc -z 127.0.0.1 "$PORT" 2>/dev/null && break
  sleep 0.3
done
if ! nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
  err "Tunnel port $PORT did not come up."
  exit 1
fi
ok "Tunnel is up on 127.0.0.1:$PORT"

# ---- 3. act per mode ------------------------------------------------------
if [ "$MODE" = "check" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:$PORT/" || echo 000)"
  if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "302" ]; then
    ok "Dashboard reachable through tunnel (HTTP $code). Self-test passed."
    exit 0
  else
    err "Dashboard not reachable through tunnel (HTTP $code)."
    exit 1
  fi
fi

printf '\n%s\n\n' "$URL"

if [ "$MODE" = "open" ]; then
  if command -v open >/dev/null 2>&1; then open "$URL"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
  else log "Open the URL above in your browser."; fi
  ok "Browser launched."
fi

# keep the tunnel alive in the foreground (only if we own it)
if [ -n "$TUN" ]; then
  log "Tunnel running. Press Ctrl-C to close it."
  wait "$TUN"
else
  log "Using a pre-existing tunnel; not holding it open. Run './nemoclaw-connect.sh stop' to close it."
fi
