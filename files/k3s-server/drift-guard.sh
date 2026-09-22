#!/usr/bin/env bash
# ExecStartPre drift guard for single-server embedded-etcd k3s.
#
# The etcd member peer URL is registered at the node IP current when the
# cluster was initialized (or last reset). On a DHCP host a new lease leaves
# the registered peer URL pointing at the old IP and k3s fails to start:
#   "Failed to test etcd connection: this server is a not a member of the etcd
#    cluster. Found [...=https://OLD:2380], expect: [...=https://NEW:2380]"
#
# Two modes:
#   pinned ($NODE_IP set in env, e.g. a static secondary address):
#       verify the pin is assigned locally and stand aside. While the pin
#       holds, --node-ip keeps the peer URL stable and drift cannot happen.
#   auto  (no pin): compare the detected node IP (kubelet's default-route
#       algorithm) against var/drift.state; on drift, run a one-shot
#           k3s server --cluster-reset --node-ip=<new>
#       which re-points the etcd member peer URL (data preserved;
#       SINGLE-SERVER only), then let the unit start normally.
#
# Related tools: reset.sh (manual remedy / re-pinning), restore.sh (snapshot
# restore), etcd.sh (inspection), status.sh (read-only report).
#
# Runs as root from the unit; also safe to invoke by hand. Nonzero exit
# blocks the k3s start (systemd Restart=always retries every RestartSec).
# Journal tag: k3s-drift-guard
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TAG="k3s-drift-guard"
STATE_FILE="$DIR/var/drift.state"

log()  { logger -t "$TAG" -p user.info    -- "$*" 2>/dev/null || true; printf '[%s] %s\n' "$TAG" "$*" >&2; }
warn() { logger -t "$TAG" -p user.warning -- "$*" 2>/dev/null || true; printf '[%s] WARNING: %s\n' "$TAG" "$*" >&2; }

persist_state() {
  printf '%s\n' "$1" | as_root tee "$STATE_FILE" >/dev/null 2>&1 \
    || warn "could not persist baseline to $STATE_FILE (will re-baseline next start)"
}

# --- pinned mode -------------------------------------------------------------
if [ -n "${NODE_IP:-}" ]; then
  if ip_assigned_locally "$NODE_IP"; then
    log "pinned node IP $NODE_IP is assigned; etcd peer URL held by --node-ip; ok"
    exit 0
  fi
  warn "NODE_IP=$NODE_IP is not assigned on any interface; blocking k3s start"
  warn "fix the static-address drop-in (systemd-iface-extra-addr.etc.pb) or unset NODE_IP"
  exit 1
fi

# --- auto mode ---------------------------------------------------------------
current_ip="$(detect_node_ip)"
if [ -z "$current_ip" ]; then
  warn "could not detect node IP from default route; starting anyway (k3s will fail loudly if wrong)"
  exit 0
fi

if [ ! -d "$DB_DIR" ]; then
  log "fresh install (no db yet); seeding drift baseline $current_ip"
  persist_state "$current_ip"
  exit 0
fi

last_ip=""
[ -r "$STATE_FILE" ] && last_ip="$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null || true)"

if [ -z "$last_ip" ]; then
  log "no drift baseline; seeding $current_ip (no reset)"
elif [ "$current_ip" != "$last_ip" ]; then
  warn "DRIFT: node IP changed '$last_ip' -> '$current_ip'"
  warn "one-shot k3s --cluster-reset --node-ip=$current_ip (re-points etcd member peer URL, data preserved)"
  if as_root "$K3S_BIN" server --cluster-reset --data-dir="$DATA" --node-ip="$current_ip" >/dev/null 2>&1; then
    log "cluster-reset ok; member peer URL now $current_ip:2380"
    stash_creds_for_reset >&2 || true
  else
    rc=$?
    warn "cluster-reset failed (rc=$rc); blocking start so systemd retries (journalctl -u $NAME for k3s output)"
    exit "$rc"
  fi
else
  log "no drift ($current_ip matches baseline)"
fi

persist_state "$current_ip"
exit 0
