#!/usr/bin/env bash
# Manual one-shot cluster-reset for SINGLE-SERVER embedded-etcd k3s.
#
# Rewrites the etcd member peer URL to a target IP:
#   - after DHCP drift (registered OLD_IP -> current IP), or
#   - when moving the cluster onto a static node IP pin (--node-ip).
# Data is preserved: cluster-reset is etcd's --force-new-cluster over the
# existing db, and k3s re-points the member peer URL to --node-ip.
#
# !!! SINGLE-SERVER ONLY !!! cluster-reset resets etcd membership to a
# single member; on multi-server it severs this node from its peers (each
# peer must then be wiped at db/ and re-joined). The member-count guard
# refuses to run on a multi-member cluster; multi-server peer drift is a
# runbook (etcdctl member remove on a healthy peer), not a script.
#
# Use when k3s fails with:
#   "Failed to test etcd connection: this server is a not a member of the etcd
#    cluster. Found [...=https://OLD:2380], expect: [...=https://NEW:2380]"
#
# Usage:
#   ./reset.sh                     # interactive; target = $NODE_IP or detected
#   ./reset.sh --yes               # skip the prompt
#   ./reset.sh 192.168.1.8         # explicit target IP (e.g. new static pin)
#   ./reset.sh --yes 192.168.1.8
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

yes=0
target=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes=1 ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) target="$arg" ;;
  esac
done

node_ip="$(effective_node_ip "$target")"
if [ -z "$node_ip" ]; then
  echo "ERROR: no target IP (pass one explicitly, set NODE_IP, or fix the default route)" >&2
  exit 1
fi

refuse_if_multiserver

echo "Target node IP : $node_ip${target:+ (explicit)}"
echo "k3s data dir   : $DATA"
echo "unit           : $NAME.service"
echo

if [ "$yes" -ne 1 ]; then
  echo "About to:"
  echo "  1. stop $NAME.service (if running)"
  echo "  2. k3s server --cluster-reset --node-ip=$node_ip"
  echo "     (data preserved, etcd member peer URL re-pointed; SINGLE-SERVER ONLY)"
  echo "  3. stash server/cred files newer than the datastore (k3s recreates"
  echo "     them from datastore; encryption files always preserved)"
  echo
  printf "Press Ctrl-C to abort, Enter to continue: "
  read -r _
fi

echo "==> stopping $NAME.service"
as_root systemctl stop "$NAME" 2>/dev/null || true

echo "==> cluster-reset at $node_ip"
as_root "$K3S_BIN" server --cluster-reset --data-dir="$DATA" --node-ip="$node_ip"

stash_creds_for_reset
printf '%s\n' "$node_ip" | as_root tee "$DIR/var/drift.state" >/dev/null
echo "==> drift baseline updated to $node_ip"

echo
echo "Done. Start k3s with:"
echo "  sudo systemctl start $NAME"
