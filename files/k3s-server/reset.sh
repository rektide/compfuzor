#!/usr/bin/env bash
# Manual one-shot cluster-reset for SINGLE-SERVER embedded-etcd k3s.
#
# Runs `k3s server --cluster-reset --node-ip=<current>` to rewrite the etcd
# member peer URL after node-IP drift (DHCP changes, etc.).
#
# !!! SINGLE-SERVER ONLY !!!
# cluster-reset is etcd's --force-new-cluster: it preserves the local data
# dir but resets cluster membership to a single member. On multi-server it
# severs this node from its peers (each peer must then be wiped at db/ and
# re-joined). This script checks member count and refuses if >1. For
# multi-server recovery, use `etcdctl member remove`/`member add` against a
# healthy peer -- that's a runbook, not a script.
#
# Use this when k3s is failing to start with:
#   "Failed to test etcd connection: this server is a not a member of the etcd
#    cluster. Found [...=https://OLD_IP:2380], expect: [...=https://NEW_IP:2380]"
#
# Usage:
#   ./reset.sh              # interactive (prompts before stopping k3s)
#   ./reset.sh --yes        # skip the prompt

set -euo pipefail

INSTANCE_DIR="/srv/k3s-server-workhorse-voodoowarez-com"
ENV_FILE="${INSTANCE_DIR}/env"
K3S_BIN="/usr/local/bin/k3s"

[ -r "$ENV_FILE" ] && . "$ENV_FILE"
: "${DATA:=/var/lib/k3s-server-workhorse-voodoowarez-com/data}"

current_ip="$(ip -4 route get 1.1.1.1 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"

if [ -z "$current_ip" ]; then
  echo "ERROR: could not detect current node IP" >&2
  exit 1
fi

echo "Detected current node IP : $current_ip"
echo "k3s data dir            : $DATA"
echo

# --- multi-server guard: refuse if etcd reports >1 member ---
ETCD_TLS_DIR="$DATA/server/tls/etcd"
if sudo test -r "$ETCD_TLS_DIR/server-client.crt" 2>/dev/null; then
  member_count="$(sudo /usr/bin/etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert="$ETCD_TLS_DIR/server-ca.crt" \
    --cert="$ETCD_TLS_DIR/server-client.crt" \
    --key="$ETCD_TLS_DIR/server-client.key" \
    member list 2>/dev/null | grep -c '^' || true)"
  if [ "${member_count:-0}" -gt 1 ]; then
    echo "ERROR: etcd reports $member_count members -- multi-server cluster." >&2
    echo "  --cluster-reset would sever this node from its peers." >&2
    echo "  For peer-URL drift: etcdctl member remove <stale-id> on a healthy peer," >&2
    echo "  then restart this node to rejoin." >&2
    exit 1
  fi
fi

if [ "${1:-}" != "--yes" ]; then
  echo "About to:"
  echo "  1. stop k3s-server.service (if running)"
  echo "  2. run k3s --cluster-reset --node-ip=$current_ip"
  echo "     (preserves data, rewrites peer URL; SINGLE-SERVER ONLY)"
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

echo
echo "Done. Start k3s with:"
echo "  sudo systemctl start k3s-server.service"
