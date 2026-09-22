#!/usr/bin/env bash
# Diagnostic overview for the k3s-server instance, focused on the
# IP-drift failure mode. Read-only. Uses sudo where needed (etcd certs,
# listeners, snapshots). Run any time.
#
# Usage:
#   ./status.sh                 # full report
#   ./status.sh --no-color      # plain output (for piping)

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

COLOR=${COLOR:-1}
[ "${1:-}" = "--no-color" ] && COLOR=0

if [ "$COLOR" = 1 ]; then
  HDR=$'\033[1;36m'; RST=$'\033[0m'; RED=$'\033[1;31m'; GRN=$'\033[1;32m'; YLW=$'\033[1;33m'
else
  HDR=""; RST=""; RED=""; GRN=""; YLW=""
fi

hr() { printf '\n%s-- %s --%s\n' "$HDR" "$*" "$RST"; }

# --- service
hr "service"
printf 'active:   %s\n' "$(systemctl is-active "$NAME" 2>&1)"
printf 'enabled:  %s\n' "$(systemctl is-enabled "$NAME" 2>&1)"
printf 'topology: %s\n' "$( [ "${K3S_MULTISERVER:-0}" = "1" ] && echo multi-server || echo single-server )"
systemctl show "$NAME" -p ActiveEnterTimestamp -p ExecMainPID -p Result 2>/dev/null \
  | tr ' ' '\n' | sed 's/^/  /'

# --- node IP
hr "node IP (kubelet selection)"
current_ip="$(detect_node_ip)"
printf 'current (default-route src): %s\n' "${current_ip:-<undetectable>}"

printf '\nnode-IP pin: '
if [ -n "${NODE_IP:-}" ]; then
  if ip_assigned_locally "$NODE_IP"; then
    printf '%s (pinned, assigned)%s\n' "$GRN$NODE_IP" "$RST"
  else
    printf '%s (pinned, NOT ASSIGNED -- drift-guard will block start)%s\n' "$RED$NODE_IP" "$RST"
  fi
else
  printf '(none; drift-guard auto mode)%s\n' "$YLW"
fi

printf 'drift baseline (var/drift.state): '
if [ -r "$DIR/var/drift.state" ]; then
  printf '%s\n' "$(tr -d '[:space:]' < "$DIR/var/drift.state")"
else
  printf '%s(none -- drift-guard will seed on next start)%s\n' "$YLW" "$RST"
fi

printf '\ndefault route:\n'
ip -4 route show default 2>/dev/null | sed 's/^/  /'

# --- listeners
hr "listeners (etcd 2379/2380, apiserver 6443, kubelet 10250)"
as_root ss -ltnp 2>/dev/null | grep -E ':(2379|2380|6443|10250)\b' | sed 's/^/  /' \
  || echo "  (none / sudo needed)"

# --- etcd member list (the cached peer URL that drift breaks)
hr "etcd member list (registered peer URLs)"
if as_root test -r "$ETCD_TLS_DIR/server-client.crt" 2>/dev/null; then
  member_output="$(etcdctl_live member list 2>&1 || true)"
  echo "$member_output" | sed 's/^/  /'
  member_count="$(echo "$member_output" | grep -c '^' || true)"
  echo
  if [ "${member_count:-0}" -gt 1 ]; then
    printf '  %sMULTI-SERVER: %s members. reset.sh will refuse.%s\n' "$YLW" "$member_count" "$RST"
  elif [ -n "$current_ip" ]; then
    if echo "$member_output" | grep -q "=https://${current_ip}:2380"; then
      printf '  %speer URL matches current IP%s\n' "$GRN" "$RST"
    else
      printf '  %sDRIFT: current IP %s not in peer URLs; reset.sh can fix%s\n' "$RED" "$current_ip" "$RST"
    fi
  fi
else
  echo "  (cannot read $ETCD_TLS_DIR; sudo needed, or k3s not yet started)"
fi

# --- snapshots
hr "etcd snapshots (latest 5)"
as_root "$K3S_BIN" etcd-snapshot list --data-dir="$DATA" 2>/dev/null | tail -5 | sed 's/^/  /' \
  || echo "  (k3s etcd-snapshot list failed)"

# --- off-box snapshot sink
hr "off-box snapshot sink"
if [ -n "${ETCD_SNAPSHOT_SINK:-}" ]; then
  printf 'sink: %s\n' "$ETCD_SNAPSHOT_SINK"
  if as_root test -d "$ETCD_SNAPSHOT_SINK" 2>/dev/null; then
    count="$(as_root ls -1 "$ETCD_SNAPSHOT_SINK" 2>/dev/null | grep -v '^creds$' | wc -l)"
    newest="$(as_root ls -1t "$ETCD_SNAPSHOT_SINK" 2>/dev/null | grep -v '^creds$' | head -n1)"
    printf 'contents: %s file(s); newest: %s\n' "$count" "${newest:-(none)}"
    printf 'timer: %s\n' "$(systemctl is-active "$NAME-snapshot-sync.timer" 2>&1)"
    if as_root test -f "$ETCD_SNAPSHOT_SINK/creds/token" 2>/dev/null; then
      printf 'DR creds: %s\n' "mirrored (token present)"
    else
      printf 'DR creds: %s\n' "not mirrored (ETCD_SNAPSHOT_SINK_CREDS=true to enable)"
    fi
  else
    printf '%s unreachable%s\n' "$RED" "$RST"
  fi
else
  printf '(ETCD_SNAPSHOT_SINK unset; no off-box sync)\n'
fi

# --- the actual failure signature
hr "recent 'not a member of the etcd cluster' (last 3, 24h)"
journalctl -u "$NAME" --no-pager --since "24 hours ago" 2>&1 \
  | grep "Failed to test etcd" | tail -3 | sed 's/^/  /' || true

echo
