#!/usr/bin/env bash
# Diagnostic overview for the k3s-server instance, focused on the
# IP-drift failure mode. Read-only. Uses sudo where needed (etcd certs,
# listeners, snapshots). Run any time.
#
# Usage:
#   ./status.sh                 # full report
#   ./status.sh --no-color      # plain output (for piping)

set -euo pipefail

INSTANCE_DIR="/srv/k3s-server-workhorse-voodoowarez-com"
ENV_FILE="${INSTANCE_DIR}/env"
STATE_FILE="${INSTANCE_DIR}/var/drift.state"
K3S_BIN="/usr/local/bin/k3s"

[ -r "$ENV_FILE" ] && . "$ENV_FILE"
: "${DATA:=/var/lib/k3s-server-workhorse-voodoowarez-com/data}"

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
printf 'active:   %s\n' "$(systemctl is-active k3s-server.service 2>&1)"
printf 'enabled:  %s\n' "$(systemctl is-enabled k3s-server.service 2>&1)"
systemctl show k3s-server.service -p ActiveEnterTimestamp -p ExecMainPID -p Result 2>/dev/null \
  | tr ' ' '\n' | sed 's/^/  /'

# --- node IP
hr "node IP (kubelet selection)"
current_ip="$(ip -4 route get 1.1.1.1 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
printf 'current (default-route src): %s\n' "${current_ip:-<undetectable>}"

last_ip="(none)"
[ -r "$STATE_FILE" ] && last_ip="$(tr -d '[:space:]' < "$STATE_FILE")"
printf 'last-known (%s): %s\n' "$STATE_FILE" "$last_ip"

if [ -n "$current_ip" ] && [ "$last_ip" != "(none)" ]; then
  if [ "$current_ip" = "$last_ip" ]; then
    printf 'drift:    %sno%s\n' "$GRN" "$RST"
  else
    printf 'drift:    %sYES (%s -> %s); launch.sh will reset on next start%s\n' "$RED" "$last_ip" "$current_ip" "$RST"
  fi
elif [ -z "$last_ip" ] || [ "$last_ip" = "(none)" ]; then
  printf 'drift:    %sunknown (no baseline; launch.sh will seed on first run)%s\n' "$YLW" "$RST"
fi

printf '\ndefault route:\n'
ip -4 route show default 2>/dev/null | sed 's/^/  /'

# --- listeners
hr "listeners (etcd 2379/2380, apiserver 6443, kubelet 10250)"
sudo ss -ltnp 2>/dev/null | grep -E ':(2379|2380|6443|10250)\b' | sed 's/^/  /' \
  || echo "  (none / sudo needed)"

# --- etcd member list (the cached peer URL that drift breaks)
hr "etcd member list (registered peer URLs)"
ETCD_TLS_DIR="$DATA/server/tls/etcd"
if sudo test -r "$ETCD_TLS_DIR/server-client.crt" 2>/dev/null; then
  sudo /usr/bin/etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert="$ETCD_TLS_DIR/server-ca.crt" \
    --cert="$ETCD_TLS_DIR/server-client.crt" \
    --key="$ETCD_TLS_DIR/server-client.key" \
    member list 2>&1 | sed 's/^/  /' || true
  echo
  echo "  note: 'member update' won't work in the drift-broken state -- the"
  echo "  registered peer is unreachable so raft has no leader to commit. Use"
  echo "  bin/recover.sh to rewrite via --cluster-reset."
else
  echo "  (cannot read $ETCD_TLS_DIR; sudo needed, or k3s not yet started)"
fi

# --- snapshots
hr "etcd snapshots (latest 5)"
sudo "$K3S_BIN" etcd-snapshot list --data-dir="$DATA" 2>/dev/null | tail -5 | sed 's/^/  /' \
  || echo "  (k3s etcd-snapshot list failed)"

# --- drift/reset events
hr "recent k3s-launcher events (last 10)"
journalctl -t k3s-launcher --no-pager -n 10 2>&1 \
  | tail -10 | sed 's/^/  /' || true

# --- the actual failure signature
hr "recent 'not a member of the etcd cluster' (last 3, 24h)"
journalctl -t k3s-server-workhorse-voodoowarez-com --no-pager --since "24 hours ago" 2>&1 \
  | grep "Failed to test etcd" | tail -3 | sed 's/^/  /' || true

echo
