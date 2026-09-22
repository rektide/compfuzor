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
# Also mirror DR credentials (cluster token, agent token, secrets-encryption
# key) to <sink>/creds/. A snapshot alone is unrestorable on fresh hardware:
# without the token k3s refuses the restore, and without the encryption key
# every encrypted secret is unreadable. NOTE: the sink then holds live cluster
# secrets -- protect the share accordingly.
SINK_CREDS="${ETCD_SNAPSHOT_SINK_CREDS:-false}"

[ -n "$SINK" ] || { echo "ERROR: no sink (pass a path or set ETCD_SNAPSHOT_SINK)" >&2; exit 64; }
[ -d "$SNAPSHOTS_DIR" ] || { echo "no snapshots dir yet ($SNAPSHOTS_DIR); nothing to sync"; exit 0; }

# autofs/CIFS: stat-ing the path triggers the mount
if ! as_root test -d "$SINK" 2>/dev/null; then
  echo "ERROR: sink $SINK unreachable" >&2
  exit 1
fi

as_root mkdir -p "$SINK"
# snapshots are immutable once written, so this is a no-clobber copy: reruns
# only copy new zips (~2.7 MB each). Copy files individually: `$dir/.` is a
# directory and plain cp (without -R) silently does no useful work.
while IFS= read -r -d '' snapshot; do
  as_root cp -n --preserve=timestamps "$snapshot" "$SINK/"
done < <(as_root find "$SNAPSHOTS_DIR" -maxdepth 1 -type f -name '*.zip' -print0)

# Prune only snapshot zips. The sink can also contain cold-db archives,
# checksum manifests, and creds/; none of those are retention candidates.
as_root sh -c "cd '$SINK' && find . -maxdepth 1 -type f -name '*.zip' -printf '%T@ %f\\n' | sort -nr | tail -n +$((SINK_KEEP + 1)) | cut -d' ' -f2- | xargs -r rm -f --"

if [ "$SINK_CREDS" = "true" ]; then
  as_root mkdir -p "$SINK/creds"
  for f in "$K3S_TOKEN_FILE" "$K3S_AGENT_TOKEN_FILE" "$CRED_DIR/encryption-config.json"; do
    [ -n "${f:-}" ] || continue
    if as_root test -r "$f" 2>/dev/null; then
      as_root cp -f --preserve=timestamps "$f" "$SINK/creds/$(basename "$f")"
    fi
  done
fi

count="$(as_root find "$SINK" -maxdepth 1 -type f -name '*.zip' | wc -l)"
newest="$(as_root find "$SINK" -maxdepth 1 -type f -name '*.zip' -printf '%T@ %f\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
creds_note=""
[ "$SINK_CREDS" = "true" ] && creds_note="; creds mirrored"
echo "synced: $count snapshot(s) in $SINK; newest: ${newest:-(none)}${creds_note}"
