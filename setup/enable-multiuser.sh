#!/usr/bin/env bash
#
# enable-multiuser.sh — let OTHER local accounts on the DGX Spark use the shared
# AI stack (one ComfyUI + one NemoClaw assistant + the Ollama service), each
# reached over their own SSH tunnel.
#
# Run ONCE on the Spark, as the service owner (arts), with sudo:
#     sudo bash setup/enable-multiuser.sh alice bob carol
#     sudo bash setup/enable-multiuser.sh --add dave      # add one more later
#     sudo bash setup/enable-multiuser.sh                 # just (re)install wrappers
#
# What it does, and WHY each piece is needed:
#   - Ollama already listens on 127.0.0.1:11434 (systemd, system-wide) → every
#     local user can reach it; nothing to do there.
#   - ComfyUI binds 127.0.0.1:8188 → any local user's SSH tunnel forwards to it.
#     They don't need filesystem access (they drive it through the web UI). The
#     only gap is being able to (re)START it when it's down, which must happen as
#     the owner → we install a tiny wrapper + a NOPASSWD sudo rule for that.
#   - NemoClaw's dashboard needs a fresh token from the owner's `nemoclaw` CLI,
#     which other users don't have → same pattern: a wrapper run as the owner via
#     a scoped NOPASSWD sudo rule.
#
# Security: the sudo rule grants ONLY these two fixed commands, only to members
# of the `dgx-ai` group, only as the owner account — not a general shell.
#
set -euo pipefail

GROUP="${DGX_GROUP:-dgx-ai}"
OWNER="${DGX_OWNER:-${SUDO_USER:-$(id -un)}}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo bash setup/enable-multiuser.sh [users...]" >&2
  exit 1
fi

OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"
if [ -z "$OWNER_HOME" ] || [ ! -d "$OWNER_HOME" ]; then
  echo "Could not resolve home dir for owner '$OWNER'. Set DGX_OWNER explicitly." >&2
  exit 1
fi

# Collect the user list (everything that isn't the --add flag).
ADD_USERS=()
for a in "$@"; do
  [ "$a" = "--add" ] && continue
  ADD_USERS+=("$a")
done

echo "Owner account : $OWNER  (home: $OWNER_HOME)"
echo "Access group  : $GROUP"
echo "Users to add  : ${ADD_USERS[*]:-(none — just installing wrappers)}"
echo

# ---- 1. group + membership ------------------------------------------------
if ! getent group "$GROUP" >/dev/null; then
  groupadd "$GROUP"
  echo "[group] created '$GROUP'"
else
  echo "[group] '$GROUP' already exists"
fi
for u in "${ADD_USERS[@]:-}"; do
  [ -z "$u" ] && continue
  if ! id "$u" >/dev/null 2>&1; then
    echo "[group] WARNING: user '$u' does not exist on this box — skipping" >&2
    continue
  fi
  usermod -aG "$GROUP" "$u"
  echo "[group] added '$u' to '$GROUP' (they must log out/in for it to take effect)"
done

# ---- 2. wrappers (run AS the owner via sudo) ------------------------------
cat > /usr/local/bin/nemoclaw-dashboard-url <<EOF
#!/usr/bin/env bash
# Print a fresh tokenized NemoClaw dashboard URL. Meant to be invoked as the
# owner: sudo -u $OWNER /usr/local/bin/nemoclaw-dashboard-url [sandbox]
export HOME="$OWNER_HOME"
export PATH="\$HOME/.local/bin:/usr/local/bin:\$PATH"
exec nemoclaw "\${1:-spark-assistant}" dashboard-url --quiet
EOF
chmod 0755 /usr/local/bin/nemoclaw-dashboard-url
echo "[wrapper] /usr/local/bin/nemoclaw-dashboard-url"

cat > /usr/local/bin/comfyui-ensure <<EOF
#!/usr/bin/env bash
# Idempotently ensure the shared ComfyUI is running. Meant to be invoked as the
# owner: sudo -u $OWNER /usr/local/bin/comfyui-ensure
export HOME="$OWNER_HOME"
export PATH="/usr/local/bin:\$PATH"
exec "\$HOME/comfyui-start.sh"
EOF
chmod 0755 /usr/local/bin/comfyui-ensure
echo "[wrapper] /usr/local/bin/comfyui-ensure"

# ---- 3. scoped NOPASSWD sudo rule -----------------------------------------
SUDOERS=/etc/sudoers.d/dgx-ai
cat > "$SUDOERS" <<EOF
# Allow members of $GROUP to fetch a NemoClaw dashboard token and to (re)start
# the shared ComfyUI, both as the owner account ($OWNER), without a password.
# These are the ONLY commands granted — not a general shell.
%$GROUP ALL=($OWNER) NOPASSWD: /usr/local/bin/nemoclaw-dashboard-url, /usr/local/bin/comfyui-ensure
EOF
chmod 0440 "$SUDOERS"
if visudo -cf "$SUDOERS" >/dev/null; then
  echo "[sudoers] installed + validated $SUDOERS"
else
  echo "[sudoers] VALIDATION FAILED — removing $SUDOERS" >&2
  rm -f "$SUDOERS"
  exit 1
fi

echo
echo "Done. Each added user now, from THEIR OWN laptop:"
echo "  1. can SSH to the Spark as their own account (key-based login set up),"
echo "  2. copies client/dgx.conf.example → client/dgx.conf and sets"
echo "       CU_HOST / NC_HOST = <their-spark-user>@dgx.zrh.arts.moe"
echo "  3. runs  bash client/comfyui-connect.sh  and  bash client/nemoclaw-connect.sh"
echo
echo "See MULTIUSER.md for the full per-user walkthrough."
