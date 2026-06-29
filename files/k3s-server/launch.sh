#!/usr/bin/env bash
# Drift-detecting pass-through launcher for k3s server.
#
# Usage in unit:
#   ExecStart=/srv/k3s-server-workhorse-voodoowarez-com/bin/launch.sh \
#     /usr/local/bin/k3s server [steady-state-args...]
#
# All steady-state k3s args come from the unit (passed through via "$@"). The
# launcher's job is narrowly:
#
#   - Detect the current node IP (IPv4 src of the default route, the same
#     algorithm kubelet uses when --node-ip is unset) and log it.
#   - Compare against the baseline in $STATE_FILE; on drift, run a one-shot
#     `k3s server --cluster-reset --cluster-reset-keep-control-plane-members`
#     at the new IP to rewrite the etcd member peer URL (preserves data).
#   - Decide bootstrap: if the etcd data dir is empty AND no snapshots exist,
#     append --cluster-init. Otherwise do not.
#   - Append --node-ip=<current> so k3s's notion of node IP matches what we
#     just reset against.
#   - exec "$@" with the appended flags.
#
# Only node-IP drift triggers a reset. Other failure modes are left to the
# operator (use bin/recover.sh for manual cluster-reset).
#
# Drift/reset events are tagged "k3s-launcher" in the journal:
#   journalctl -t k3s-launcher

set -euo pipefail

INSTANCE_DIR="/srv/k3s-server-workhorse-voodoowarez-com"
ENV_FILE="${INSTANCE_DIR}/env"
STATE_FILE="${INSTANCE_DIR}/var/drift.state"
K3S_BIN="/usr/local/bin/k3s"
TAG="k3s-launcher"

# load env (for $DATA and any other paths). best-effort.
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi
: "${DATA:=/var/lib/k3s-server-workhorse-voodoowarez-com/data}"

log()  { logger -t "$TAG" -p user.info    -- "$*" 2>/dev/null || true; printf '[%s] %s\n' "$TAG" "$*" >&2; }
warn() { logger -t "$TAG" -p user.warning -- "$*" 2>/dev/null || true; printf '[%s] WARNING: %s\n' "$TAG" "$*" >&2; }

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || warn "could not mkdir $(dirname "$STATE_FILE")"

# --- 1. detect current node IP (kubelet's algorithm: src of default route)
current_ip="$(ip -4 route get 1.1.1.1 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
log "current node IP: ${current_ip:-<undetectable>}"

# --- 2. read baseline
last_ip="(none)"
if [ -r "$STATE_FILE" ]; then
  last_ip="$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null || true)"
  [ -z "$last_ip" ] && last_ip="(none)"
fi
log "baseline IP (from $STATE_FILE): $last_ip"

# --- 3+4. drift check + reset
if [ -z "$current_ip" ]; then
  warn "could not detect node IP from default route; skipping drift check"
elif [ "$last_ip" = "(none)" ]; then
  log "no baseline; seeding with '$current_ip' (no reset)"
elif [ "$current_ip" != "$last_ip" ]; then
  warn "DRIFT: node IP changed: '$last_ip' -> '$current_ip'"
  warn "running k3s --cluster-reset --cluster-reset-keep-control-plane-members to rewrite etcd member peer URL"
  if "$K3S_BIN" server \
      --cluster-reset \
      --cluster-reset-keep-control-plane-members \
      --data-dir="$DATA" \
      --node-ip="$current_ip" >/dev/null 2>&1 ; then
    log "cluster-reset OK; etcd member peer URL rewritten to '$current_ip'"
  else
    rc=$?
    warn "cluster-reset failed (rc=$rc); aborting so systemd can retry"
    exit "$rc"
  fi
else
  log "no drift (current matches baseline)"
fi

# --- 5. persist baseline (atomic write)
if [ -n "$current_ip" ]; then
  tmp="${STATE_FILE}.$$"
  if printf '%s\n' "$current_ip" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_FILE" 2>/dev/null; then
    :
  else
    warn "could not persist baseline to $STATE_FILE (drift detection will re-baseline next run)"
  fi
fi

# --- 6. decide bootstrap flag
# --cluster-init is bootstrap-only. Add it if there's no etcd data AND no
# snapshots to restore from; otherwise let k3s detect existing state.
extra_args=()
if [ -d "$DATA/server/db/etcd" ] && [ -n "$(ls -A "$DATA/server/db/etcd" 2>/dev/null)" ]; then
  log "existing etcd data at $DATA/server/db/etcd; not bootstrapping"
elif [ -d "$DATA/server/db/snapshots" ] && [ -n "$(ls -A "$DATA/server/db/snapshots" 2>/dev/null)" ]; then
  warn "no live etcd data but snapshots exist; k3s will restore on start (no --cluster-init)"
else
  warn "fresh install: no etcd data and no snapshots; appending --cluster-init"
  extra_args+=(--cluster-init)
fi

# --- 7. inject --node-ip so k3s agrees with the IP we reset against
if [ -n "$current_ip" ]; then
  extra_args+=(--node-ip="$current_ip")
fi

# --- 8. hand off to the wrapped command
if [ "$#" -eq 0 ]; then
  warn "no command passed; expected: launch.sh /usr/local/bin/k3s server [args...]"
  exit 64
fi
log "exec'ing: $* ${extra_args[*]}"
if [ "${#extra_args[@]}" -gt 0 ]; then
  exec "$@" "${extra_args[@]}"
else
  exec "$@"
fi
