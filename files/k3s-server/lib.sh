#!/usr/bin/env bash
# Shared helpers for the k3s-server ops scripts. Sourced, not executed.
#
# Scripts here live in <DIR>/bin (DIR: the compfuzor subsystem dir, e.g.
# /srv/k3s-server-<instance>). Helpers locate the instance via BASH_SOURCE,
# load <DIR>/env, and wrap root-privileged calls so every script is equally
# at home run by hand (sudo as needed) or from a root systemd unit.
#
# Notable paths:
#   DATA                       k3s --data-dir (typically a /var/lib/... target)
#   $DATA/server/db/etcd       embedded etcd member data
#   $DATA/server/db/snapshots  etcd snapshot zips (12h cadence, retention N)
#   $DATA/server/cred          cluster credential files (DO NOT lose these)

# --- instance discovery ------------------------------------------------------
_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(cd -- "$_LIB_DIR/.." && pwd)"

ENV_FILE="${ENV_FILE:-$DIR/env}"
# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

: "${NAME:=k3s-server}"
: "${DATA:=$DIR/var/data}"
: "${K3S_BIN:=/usr/local/bin/k3s}"
# k3s v1.36 embeds etcd in-process and bundles no etcdctl, so use the system
# etcdctl (3.5.x). The v3 gRPC API is stable across 3.5/3.6; member list,
# endpoint health, and snapshot status work against the embedded server.
: "${ETCDCTL:=/usr/bin/etcdctl}"

ETCD_TLS_DIR="$DATA/server/tls/etcd"
DB_DIR="$DATA/server/db"
SNAPSHOTS_DIR="$DB_DIR/snapshots"
CRED_DIR="$DATA/server/cred"

# --- root --------------------------------------------------------------------
# Run a command as root: directly under the unit (ExecStartPre/ExecStart run
# as root), via sudo when invoked by hand.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# --- node IP -----------------------------------------------------------------
# kubelet's default node-IP algorithm: IPv4 src address of the default route.
detect_node_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i+1); exit}}' || true
}

# Effective node IP: explicit argument > $NODE_IP (static pin) > autodetect.
# Prints the IP; prints nothing if undetectable.
effective_node_ip() {
  if [ -n "${1:-}" ]; then printf '%s\n' "$1"
  elif [ -n "${NODE_IP:-}" ]; then printf '%s\n' "$NODE_IP"
  else detect_node_ip
  fi
}

# Exact match: is this IPv4 address assigned on any interface?
ip_assigned_locally() {
  ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -qxF "$1"
}

# --- etcd guards -------------------------------------------------------------
# Live member count (0 when etcd is down/unreachable). Only meaningful while
# the server is running.
etcd_member_count() {
  as_root "$ETCDCTL" \
    --endpoints=https://127.0.0.1:2379 \
    --cacert="$ETCD_TLS_DIR/server-ca.crt" \
    --cert="$ETCD_TLS_DIR/server-client.crt" \
    --key="$ETCD_TLS_DIR/server-client.key" \
    member list 2>/dev/null | grep -c '^' || true
}

# etcdctl with the k3s etcd client certs against the local embedded server.
etcdctl_live() {
  as_root "$ETCDCTL" \
    --endpoints=https://127.0.0.1:2379 \
    --cacert="$ETCD_TLS_DIR/server-ca.crt" \
    --cert="$ETCD_TLS_DIR/server-client.crt" \
    --key="$ETCD_TLS_DIR/server-client.key" "$@"
}

# cluster-reset is etcd's --force-new-cluster: on a multi-server cluster it
# severs this node from its peers. Refuse unless etcd reports <= 1 member.
# (No-op when etcd is down -- the usual state during recovery.)
refuse_if_multiserver() {
  as_root test -r "$ETCD_TLS_DIR/server-client.crt" 2>/dev/null || return 0
  local count
  count="$(etcd_member_count)"
  if [ "${count:-0}" -gt 1 ]; then
    echo "ERROR: etcd reports $count members -- multi-server cluster." >&2
    echo "  --cluster-reset would sever this node from its peers." >&2
    echo "  For peer-URL drift on HA: etcdctl member remove <stale-id> on a" >&2
    echo "  healthy peer, then restart this node to rejoin." >&2
    return 1
  fi
}

# --- post-reset hygiene ------------------------------------------------------
# cluster-reset touches server/cred/*; a cred file left newer than the
# datastore makes k3s refuse to start ("... newer than datastore and could
# cause a cluster outage. Remove the file(s) from disk and restart to be
# recreated from datastore"). Move them aside; k3s recreates them from the
# datastore on next start. NEVER move the encryption files: without that key
# every encrypted secret in the cluster is permanently unreadable.
stash_creds_for_reset() {
  local ts f moved=0
  [ -d "$CRED_DIR" ] || return 0
  ts="$(date +%Y%m%d%H%M%S)"
  for f in "$CRED_DIR"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      encryption-config.json|encryption-state.json) continue ;;
      *.bak.*) continue ;;
    esac
    as_root mv "$f" "${f}.bak.${ts}"
    moved=$((moved + 1))
  done
  echo "==> stashed $moved cred file(s) as .bak.$ts (encryption files preserved)"
}

# --- snapshots ---------------------------------------------------------------
# Resolve a snapshot reference to an absolute path (prints it; empty when
# unresolvable). Accepts: latest (newest by mtime), an absolute path, a file
# name with or without .zip, or a bare name relative to the snapshots dir.
resolve_snapshot() {
  local want="${1:-latest}" cand newest
  if [ -f "$want" ]; then printf '%s\n' "$want"; return 0; fi
  if [ "$want" = "latest" ]; then
    newest="$(as_root ls -1t "$SNAPSHOTS_DIR" 2>/dev/null | head -n1 || true)"
    [ -n "$newest" ] && printf '%s\n' "$SNAPSHOTS_DIR/$newest"
    return 0
  fi
  for cand in "$want" "$want.zip" "$SNAPSHOTS_DIR/$want" "$SNAPSHOTS_DIR/$want.zip"; do
    if as_root test -f "$cand" 2>/dev/null; then printf '%s\n' "$cand"; return 0; fi
  done
  return 0
}
