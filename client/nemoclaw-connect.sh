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
# Config (override via env):
#   NC_HOST=dgx.zrh.arts.moe   NC_SANDBOX=spark-assistant
#
set -euo pipefail

NC_HOST="${NC_HOST:-dgx.zrh.arts.moe}"
NC_SANDBOX="${NC_SANDBOX:-spark-assistant}"
REMOTE_PATH='export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"'

c_info=$'\033[36m'; c_ok=$'\033[32m'; c_err=$'\033[31m'; c_off=$'\033[0m'
log(){ printf '%s[nemoclaw]%s %s\n' "$c_info" "$c_off" "$*" >&2; }
ok(){  printf '%s[nemoclaw]%s %s\n' "$c_ok"   "$c_off" "$*" >&2; }
err(){ printf '%s[nemoclaw]%s %s\n' "$c_err"  "$c_off" "$*" >&2; }

MODE="open"
case "${1:-}" in
  --check)   MODE="check" ;;
  --no-open) MODE="noopen" ;;
  stop)      MODE="stop" ;;
  "" )       MODE="open" ;;
  *) err "Unknown argument: $1"; exit 2 ;;
esac

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
log "Fetching authenticated dashboard URL from $NC_HOST ..."
URL="$(ssh -o ConnectTimeout=15 "$NC_HOST" \
        "$REMOTE_PATH; nemoclaw $NC_SANDBOX dashboard-url --quiet" 2>/dev/null \
        | tr -d '\r' | grep -E '^https?://' | head -1 || true)"

if [ -z "$URL" ]; then
  err "Could not retrieve the dashboard URL."
  err "Check the assistant is up:  ssh $NC_HOST 'nemoclaw $NC_SANDBOX status'"
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
