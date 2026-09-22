#!/usr/bin/env bash
# etcd/snapshot inspection & ops for k3s embedded etcd (read-mostly).
#
# Commands:
#   list               snapshot inventory (k3s etcd-snapshot ls; offline)
#   status [x|latest]  etcdctl snapshot status: hash/revision/keys/size (offline)
#   members            live member list incl. peer URLs (needs etcd up)
#   health             live endpoint health + status (needs etcd up)
#   save [name]        on-demand snapshot (compressed, like scheduled ones)
#   remove-member <id> HA stale-peer remedy: etcdctl member remove. The id is
#                      the hex member ID from `members`. Use when a server's
#                      IP changed and it cannot rejoin (join refuses duplicate
#                      node names, so the stale member must go first); the
#                      changed node then restarts with its --server join
#                      config and re-adds itself as a learner.
#                      NEVER remove the member you are running this on unless
#                      it is the last resort on a dead cluster.
#
# etcdctl note: k3s v1.36 embeds etcd in-process and bundles no etcdctl, so
# this uses the system etcdctl (3.5.x). The v3 API is stable across 3.5/3.6;
# member list, endpoint health, and snapshot status work against the
# embedded 3.6 server -- treat 3.6-only behavior as unguaranteed.
#
# Usage: ./etcd.sh <command> [args]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cmd="${1:-list}"
[ $# -gt 0 ] && shift || true

# Extract the raw etcd db file from a (possibly zipped) snapshot into a
# scratch dir; prints the db file path. Caller should rm -rf the dir.
# k3s snapshot zips contain <snapname> (the db) and <snapname>.populated.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/k3s-etcd-inspect.XXXXXX")"
trap 'as_root rm -rf "$scratch" 2>/dev/null || true' EXIT

extract_snapshot_db() {
  local snap="$1"
  case "$snap" in
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        as_root unzip -oq "$snap" -d "$scratch"
      else
        as_root python3 -m zipfile -e "$snap" "$scratch"
      fi
      find "$scratch" -maxdepth 1 -type f ! -name '*.populated' -print -quit
      ;;
    *)
      as_root cp "$snap" "$scratch/snap.db"
      printf '%s\n' "$scratch/snap.db"
      ;;
  esac
}

case "$cmd" in
  list)
    as_root "$K3S_BIN" etcd-snapshot ls --data-dir "$DATA"
    ;;

  status)
    snap="$(resolve_snapshot "${1:-latest}")"
    if [ -z "$snap" ]; then
      echo "ERROR: no snapshot resolved in $SNAPSHOTS_DIR" >&2
      exit 1
    fi
    echo "snapshot: $snap"
    db="$(extract_snapshot_db "$snap")"
    if [ -z "$db" ] || ! as_root test -s "$db"; then
      echo "ERROR: could not extract an etcd db from the snapshot" >&2
      exit 1
    fi
    as_root "$ETCDCTL" snapshot status "$db"
    ;;

  members)
    etcdctl_live member list
    ;;

  remove-member)
    member_id="${1:-}"
    if [ -z "$member_id" ]; then
      echo "usage: etcd.sh remove-member <member-id>   (ids: etcd.sh members)" >&2
      exit 64
    fi
    echo "member list before removal:"
    etcdctl_live member list | sed 's/^/  /'
    echo
    etcdctl_live member remove "$member_id"
    echo
    echo "removed $member_id; restart the affected server with its --server"
    echo "join config and it will re-add itself as a learner at its new IP"
    ;;

  health)
    etcdctl_live endpoint health
    echo
    etcdctl_live endpoint status -w table
    ;;

  save)
    save_args=(--data-dir "$DATA" --etcd-snapshot-compress)
    [ -n "${1:-}" ] && save_args+=(--name "$1")
    as_root "$K3S_BIN" etcd-snapshot save "${save_args[@]}"
    ;;

  *)
    sed -n '2,15p' "$0" >&2
    exit 64
    ;;
esac
