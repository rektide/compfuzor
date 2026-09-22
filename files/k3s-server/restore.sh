#!/usr/bin/env bash
# Restore a k3s embedded-etcd snapshot (SINGLE-SERVER).
#
#   k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>
#
# Semantics (docs.k3s.io cli/etcd-snapshot + datastore/backup-restore):
#   - --cluster-reset is REQUIRED for a restore.
#   - the current db is moved aside to db/etcd-old-<ts>/ (nothing is deleted).
#   - .zip snapshots (from --etcd-snapshot-compress) are handled transparently.
#   - the cluster token must match the snapshot's (same install: yes; a
#     "cluster token does not match" error means the snapshot is foreign).
#   - after restore, one normal start clears db/reset-flag.
#
# !!! SINGLE-SERVER ONLY !!! (same caveat as reset.sh)
#
# Usage:
#   ./restore.sh                    # list snapshots, choose interactively
#   ./restore.sh latest [--yes]     # newest snapshot
#   ./restore.sh <name|path> [--yes]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

yes=0
want=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) want="$arg" ;;
  esac
done

if [ -z "$want" ]; then
  echo "Snapshots in $SNAPSHOTS_DIR:"
  as_root "$K3S_BIN" etcd-snapshot ls --data-dir "$DATA" || true
  echo
  printf "Snapshot to restore (name | latest | Enter to abort): "
  read -r want
  [ -n "$want" ] || exit 0
fi

snap="$(resolve_snapshot "$want")"
if [ -z "$snap" ]; then
  echo "ERROR: snapshot '$want' not found (looked in $SNAPSHOTS_DIR)" >&2
  exit 1
fi

node_ip="$(effective_node_ip)"
refuse_if_multiserver

echo "Snapshot     : $snap"
echo "node IP      : ${node_ip:-<undetected; k3s will choose>}"
echo "k3s data dir : $DATA"
echo "unit         : $NAME.service"
echo

if [ "$yes" -ne 1 ]; then
  echo "About to:"
  echo "  1. stop $NAME.service (if running)"
  echo "  2. k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>"
  echo "     (current db moved to db/etcd-old-<ts>/, then snapshot restored)"
  echo "  3. stash server/cred files newer than the datastore (encryption"
  echo "     files always preserved)"
  echo
  printf "Press Ctrl-C to abort, Enter to continue: "
  read -r _
fi

echo "==> stopping $NAME.service"
as_root systemctl stop "$NAME" 2>/dev/null || true

echo "==> restoring $snap"
reset_args=(--cluster-reset --cluster-reset-restore-path="$snap" --data-dir "$DATA")
[ -n "$node_ip" ] && reset_args+=(--node-ip="$node_ip")
as_root "$K3S_BIN" server "${reset_args[@]}"

stash_creds_for_reset
if [ -n "$node_ip" ]; then
  printf '%s\n' "$node_ip" | as_root tee "$DIR/var/drift.state" >/dev/null
  echo "==> drift baseline updated to $node_ip"
fi

echo
echo "Done (previous db kept under db/etcd-old-*/). Start k3s with:"
echo "  sudo systemctl start $NAME"
