#!/usr/bin/env bash
# Manual one-shot recovery from etcd member peer-URL drift.
#
# Runs `k3s server --cluster-reset` at the current node IP, then seeds the
# drift.state file used by launch.sh.
#
# !!! SINGLE-SERVER EMBEDDED-ETCD CLUSTERS ONLY !!!
# cluster-reset is etcd's --force-new-cluster: it preserves the local data
# dir but resets cluster membership to a single member. On multi-server it
# severs this node from its peers (each peer must then be wiped at db/ and
# re-joined). For multi-server drift, use `etcdctl member remove`/`member add`
# against a healthy peer instead.
#
# Use this when k3s is failing to start with:
#   "Failed to test etcd connection: this server is a not a member of the etcd
#    cluster. Found [...=https://OLD_IP:2380], expect: [...=https://NEW_IP:2380]"
#
# This is the same operation launch.sh does automatically for FUTURE drift,
# invoked manually for the current broken state (because launch.sh refuses to
# guess whether the live etcd registry matches; recover.sh is the explicit
# operator assertion "yes, rewrite the member to my current IP").
#
# Usage:
#   ./recover.sh              # interactive (prompts before stopping k3s)
#   ./recover.sh --yes        # skip the prompt

set -euo pipefail

INSTANCE_DIR="/srv/k3s-server-workhorse-voodoowarez-com"
ENV_FILE="${INSTANCE_DIR}/env"
K3S_BIN="/usr/local/bin/k3s"
# var/ is a symlink to /var/lib/k3s-server-workhorse-voodoowarez-com; reference
# it via the instance dir so the path is relative to /srv/... as a logical unit.
STATE_FILE="${INSTANCE_DIR}/var/drift.state"

[ -r "$ENV_FILE" ] && . "$ENV_FILE"
: "${DATA:=/var/lib/k3s-server-workhorse-voodoowarez-com/data}"

current_ip="$(ip -4 route get 1.1.1.1 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"

if [ -z "$current_ip" ]; then
  echo "ERROR: could not detect current node IP" >&2
  exit 1
fi

last_ip="(none)"
[ -r "$STATE_FILE" ] && last_ip="$(tr -d '[:space:]' < "$STATE_FILE")"

echo "Detected current node IP : $current_ip"
echo "Last-known IP (state)   : $last_ip"
echo "k3s data dir            : $DATA"
echo "State file              : $STATE_FILE"
echo

if [ "${1:-}" != "--yes" ]; then
  echo "About to:"
  echo "  1. stop k3s-server.service (if running)"
  echo "  2. run k3s --cluster-reset"
  echo "     (re-registers etcd member at $current_ip, preserves data; SINGLE-SERVER ONLY)"
  echo "  3. write $current_ip to $STATE_FILE"
  echo
  printf "Press Ctrl-C to abort, Enter to continue: "
  read -r _
fi

echo "==> stopping k3s-server.service"
sudo systemctl stop k3s-server.service 2>/dev/null || true

echo "==> running cluster-reset"
sudo "$K3S_BIN" server \
  --cluster-reset \
  --data-dir="$DATA" \
  --node-ip="$current_ip"

echo "==> writing $current_ip to $STATE_FILE"
sudo mkdir -p "$(dirname "$STATE_FILE")"
echo "$current_ip" | sudo tee "$STATE_FILE" >/dev/null

echo
echo "Done. Start k3s with:"
  echo "  sudo systemctl start k3s-server.service"
echo
echo "Tail drift events with:"
  echo "  journalctl -t k3s-launcher -f"
