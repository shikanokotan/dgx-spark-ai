#!/usr/bin/env bash
#
# comfyui-add-user-workflow.sh — give each user their own workflow whose images
# save to a per-user output folder (output/<user>/) on the SHARED ComfyUI.
#
# Run ON the Spark as the owner (arts):
#     bash server/comfyui-add-user-workflow.sh lzr yue yuki
#
# What this is (and isn't): it NAMESPACES outputs per user — files land in
# ~/ComfyUI/output/<user>/ instead of one shared pile. It is NOT access control:
# it's a single ComfyUI instance with no auth, so anyone tunnelled in can still
# browse the whole gallery. For true isolation you'd need per-user instances
# (see MULTIUSER.md). This is the agreed "separate output folders" option.
#
set -euo pipefail

PY="$HOME/comfyui-env/bin/python"
BUILD="$(cd "$(dirname "$0")" && pwd)/build_workflow.py"

[ -x "$PY" ] || { echo "ComfyUI venv python not found at $PY" >&2; exit 1; }
[ "$#" -ge 1 ] || { echo "usage: $0 <user> [user2 ...]" >&2; exit 2; }

for u in "$@"; do
  "$PY" "$BUILD" "$u"
done

echo
echo "Done. Each user picks 'Qwen2512-<their-name>' in the ComfyUI Workflows menu"
echo "(refresh the menu / reload the page if it doesn't show yet — no restart needed)."
echo "Their images then save under ~/ComfyUI/output/<their-name>/."
