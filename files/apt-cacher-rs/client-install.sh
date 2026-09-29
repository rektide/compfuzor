#!/bin/bash
# client-install.sh -- push a staged 30proxy snippet to a client host.
#
# Ensures $DIR/etc/30proxy.<host> exists (generating it first via
# config-30proxy.sh if needed), then scp's it over and installs it as
# /etc/apt/apt.conf.d/30proxy on the client. The remote install needs
# passwordless sudo (or an interactive sudo prompt through ssh -t).
#
# Usage:
#   client-install.sh <host> [host=proxy ...] [--proxy-host NAME]
#
# <host> is an ssh-reachable name: tailnet MagicDNS name, mDNS
# host.local, or an address. Extra args are forwarded to
# config-30proxy.sh when a snippet has to be generated.
#
# On the client, verify with:
#   apt-get update   # journal on the server shows the client's IP
set -euo pipefail

DIR="${DIR:-$(cd "$(dirname "$(readlink -f -- "$0")")/.." && pwd)}"

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print} NR>1 && !/^#/ {exit}' "$0"; exit "${1:-0}"; }

[ $# -ge 1 ] || usage 1
case "$1" in
  -h|--help) usage 0 ;;
  --*) echo "error: first argument must be a hostname" >&2; usage 1 ;;
esac

host_spec="$1"; shift
host="${host_spec%%=*}"

snippet="$DIR/etc/30proxy.$host"
if [ ! -f "$snippet" ]; then
  echo "no $snippet; generating via config-30proxy.sh"
  "$DIR/bin/config-30proxy.sh" "$host_spec" "$@"
fi
snippet="$DIR/etc/30proxy.$host"  # regenerated above

tmp="/tmp/30proxy.compfuzor.$$"
trap 'ssh "$host" rm -f "$tmp" >/dev/null 2>&1 || true' EXIT
scp -q "$snippet" "$host:$tmp"
ssh -t "$host" "sudo install -m 0644 '$tmp' /etc/apt/apt.conf.d/30proxy && rm -f '$tmp'"
echo "installed /etc/apt/apt.conf.d/30proxy on $host"
