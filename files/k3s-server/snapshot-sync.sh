#!/usr/bin/env bash
# Copy etcd snapshots to an off-box sink, e.g. a CIFS share mounted via
# autofs (/mnt/bitblaster/backup/<name>). Driven by the generated
# <NAME>-snapshot-sync.timer (hourly); safe to run by hand.
#
# Snapshots are immutable once written, so this is a no-clobber copy: reruns
# only copy new zips (~2.7 MB each). The sink is pruned to the newest
# ETCD_SNAPSHOT_SINK_KEEP entries (default 120 = ~60 days at the 12h cadence).
#
# Sink: $1 or $ETCD_SNAPSHOT_SINK (from the unit env file). Exit 1 when the
# sink is unreachable so the timer surfaces the failure.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SINK="${1:-${ETCD_SNAPSHOT_SINK:-}}"
SINK_KEEP="${ETCD_SNAPSHOT_SINK_KEEP:-120}"

[ -n "$SINK" ] || { echo "ERROR: no sink (pass a path or set ETCD_SNAPSHOT_SINK)" >&2; exit 64; }
[ -d "$SNAPSHOTS_DIR" ] || { echo "no snapshots dir yet ($SNAPSHOTS_DIR); nothing to sync"; exit 0; }

# autofs/CIFS: stat-ing the path triggers the mount
if ! as_root test -d "$SINK" 2>/dev/null; then
  echo "ERROR: sink $SINK unreachable" >&2
  exit 1
fi

as_root mkdir -p "$SINK"
as_root cp -n --preserve=timestamps "$SNAPSHOTS_DIR/." "$SINK/"

as_root sh -c "cd '$SINK' && ls -1t | tail -n +$((SINK_KEEP + 1)) | xargs -r rm -f --"

count="$(as_root ls -1 "$SINK" | wc -l)"
newest="$(as_root ls -1t "$SINK" | head -n1)"
echo "synced: $count snapshot(s) in $SINK; newest: ${newest:-(none)}"
