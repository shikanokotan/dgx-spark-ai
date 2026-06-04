#!/usr/bin/env bash
# Start ComfyUI in a detached tmux session bound to localhost:8188.
set -e
if tmux has-session -t comfy 2>/dev/null; then
  echo "ComfyUI already running (tmux session: comfy)"; exit 0
fi
tmux new-session -d -s comfy -x 200 -y 50
tmux send-keys -t comfy "cd \$HOME/ComfyUI && source \$HOME/comfyui-env/bin/activate && python main.py --listen 127.0.0.1 --port 8188 2>&1 | tee \$HOME/comfyui.log" Enter
echo "ComfyUI started in tmux session 'comfy' on 127.0.0.1:8188"
