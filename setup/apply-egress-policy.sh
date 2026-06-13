#!/usr/bin/env bash
#
# apply-egress-policy.sh — grant the shared NemoClaw agent (`spark-assistant`)
# outbound HTTPS access to the hosts in setup/policies/internet.yaml, so its
# `web_fetch` tool works. Run ON the Spark as the owner (arts):
#
#     bash setup/apply-egress-policy.sh
#
# See setup/policies/internet.yaml for the egress allowlist and WHY it's shaped
# the way it is (OpenShell forbids allow-all; web_fetch runs as node; tls:skip).
#
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

SANDBOX="${SANDBOX:-spark-assistant}"
HERE="$(cd "$(dirname "$0")" && pwd)"
POLICY="$HERE/policies/internet.yaml"

[ -f "$POLICY" ] || { echo "Policy file not found: $POLICY" >&2; exit 1; }
command -v nemoclaw >/dev/null 2>&1 || { echo "nemoclaw not on PATH" >&2; exit 1; }

echo "Applying egress allowlist to sandbox '$SANDBOX' from $POLICY"
nemoclaw "$SANDBOX" policy-add --from-file "$POLICY" --yes

echo
echo "Verify the agent can reach the net: in a NEW NemoClaw chat, ask it to run"
echo "  web_fetch({ url: \"https://httpbin.org/ip\" })"
echo "It should return JSON. If it times out, a host likely needs 'tls: skip'"
echo "(raw passthrough) — see the notes in setup/policies/internet.yaml."
