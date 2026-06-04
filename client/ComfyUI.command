#!/bin/bash
# Double-click in Finder to connect to ComfyUI on the DGX Spark.
# Opens an SSH tunnel and launches the UI in your browser.
# Keep this Terminal window open to keep the tunnel alive; close it (or Ctrl-C) to disconnect.
cd "$(dirname "$0")"
echo "Connecting to ComfyUI on the DGX Spark..."
exec bash "$(dirname "$0")/comfyui-connect.sh"
