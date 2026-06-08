#!/usr/bin/env bash
# Rebuild the double-click launcher apps from their AppleScript sources.
# Run on a Mac:  bash client/launchers/build.sh
# Produces "Open ComfyUI.app" and "Open NemoClaw.app" in client/.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$(cd "$here/.." && pwd)"
osacompile -o "$out/Open ComfyUI.app"  "$here/comfyui.applescript"
osacompile -o "$out/Open NemoClaw.app" "$here/nemoclaw.applescript"
echo "Built: $out/Open ComfyUI.app  and  Open NemoClaw.app"
