#!/bin/bash
# networkd-static.sh — generate a static systemd-networkd .network file.
#
# WHY this exists: when you kexec into a rescue / initramfs environment to
# reformat a remote single-disk box, the rescue env MUST come up on the SAME
# IP so you can SSH back in. systemd-networkd with a deterministic static
# config is the most reliable way to guarantee that. This renders a .network
# file from a profile/env, or snapshots a live interface — IPv4 AND IPv6.
#
# (networkd is the daemon; networkctl is just the status query tool. Files
# written here are consumed by systemd-networkd.service.)
#
# MODES
#   RENDER  (default)   emit from --file profile / env / positional iface
#   GATHER  (--gather)  read a running interface and reproduce it statically
#                       (the pre-kexec snapshot)
#
# INPUT (render): --file <profile> > env vars > positional iface, in that order;
# CLI flags -o/-p always win. Profile = key=value lines (IFACE=/ADDRESS=/...),
# same shape as debinst-kexec's etc/<host>.env files.
#
# USAGE
#   networkd-static.sh --file nasu.net.env                  # render from profile
#   IFACE=eth0 ADDRESS=10.0.0.5 NETMASK=255.255.255.0 \
#     GATEWAY=10.0.0.1 networkd-static.sh                   # render from env
#   networkd-static.sh --gather --predict-name -o /mnt/rescue/etc/systemd/network
#
# RENDER env (v4):  IFACE ADDRESS [PREFIX|NETMASK] GATEWAY DNS
# RENDER env (v6):  ADDRESS6 [PREFIX6] GATEWAY6 DNS6        (PREFIX6 default 64)
# GATHER env:       (none; reads the live iface)
#
# OPTIONS
#   --file PATH         source a profile file first (render data)
#   --gather            introspect a live interface (default is render)
#   --predict-name      ask udev (net_id builtin) what systemd would name the
#                       NIC afresh, and use THAT in [Match] Name= + filename.
#                       Falls back SOFTLY to the given name if udevadm is gone
#                       or the device has no predictable name (logged, not fatal).
#   -o/--output-dir D   default /etc/systemd/network
#   -p/--priority  N    default 10 (lower sorts earlier)
#
# OUTPUT
#   stdout: the path of the .network file written (for $(...) use).
#   stderr: a single JSON status object at the end (ok/mode/iface/addrs/gateway/
#           dns/routes/problems). Soft failures collect in "problems" and do NOT
#           stop the run.
#
#   <OUTDIR>/<PRIORITY>-<iface>.network  (iface = predicted name if --predict-name)
#   ONE FILE IS ENOUGH for basic static: [Match] Name= + [Network] Address=
#   (v4+v6)/Gateway=(v4+v6)/DNS=/DHCP=no/LinkLocalAddressing=ipv6, plus one
#   [Route] per non-default static route. .link (device naming) and .netdev
#   (bridges/bonds/vlans) are NOT emitted. (For NIC-rename resilience without
#   --predict-name, hand-edit [Match] to MACAddress=<hwaddr>.)
#
# DNS: if none is resolved/given, falls back to OpenDNS + Google hardcodes
# (208.67.222.222 208.67.220.220 8.8.8.8 8.8.4.4).
#
# Host deps: iproute2 (ip) for gather; udevadm for --predict-name; coreutils.

set -euo pipefail

PROBLEMS=()
FALLBACK_DNS=(208.67.222.222 208.67.220.220 8.8.8.8 8.8.4.4)

# --- json helpers (no jq dep) ------------------------------------------------
json_escape() {            # stdin -> "escaped"
  local s; IFS= read -r s || true
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}
json_str()   { printf '%s' "$1" | json_escape; }                 # scalar -> "x"
json_opt()   { if [ -n "$1" ]; then json_str "$1"; else printf 'null'; fi; }  # "" -> null
json_arr() {                                                    # args -> ["a","b"]
  local out="[" e first=1
  for e in "$@"; do
    if [ "$first" = 1 ]; then first=0; else out+=","; fi
    out+="$(json_str "$e")"
  done
  printf '%s]' "$out"
}

die() {  # emit a JSON error object on stderr, then exit 1
  printf '{"ok":false,"error":%s}\n' "$(json_str "$*")" >&2
  exit 1
}

# dotted-quad netmask -> CIDR prefix length (valid masks are contiguous)
netmask_to_prefix() {
  local a b c d quad bits=0
  IFS=. read -r a b c d <<<"$1"
  quad=$(( (a<<24) | (b<<16) | (c<<8) | d ))
  while [ "$quad" -ne 0 ]; do bits=$(( bits + 1 )); quad=$(( quad & (quad - 1) )); done
  echo "$bits"
}

# Ask udev's net_id builtin what it would name $1 afresh; apply the default
# NamePolicy (database > onboard > slot > path). Echo name on success, rc1 else.
predict_udev_name() {
  local out name k
  command -v udevadm >/dev/null 2>&1 || return 1
  out="$(udevadm test-builtin net_id "/sys/class/net/$1" 2>&1)" || return 1
  for k in ID_NET_NAME_FROM_DATABASE ID_NET_NAME_ONBOARD ID_NET_NAME_SLOT ID_NET_NAME_PATH; do
    name="$(printf '%s\n' "$out" | grep "^${k}=" | head -1 | cut -d= -f2-)"
    if [ -n "$name" ]; then printf '%s' "$name"; return 0; fi
  done
  return 1
}

# --- arg parse ---------------------------------------------------------------
MODE=render
CLI_IFACE=""; CLI_OUTDIR=""; CLI_PRIORITY=""; FILE_ARG=""; PREDICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --render)        MODE=render ;;
    --gather)        MODE=gather ;;
    --predict-name)  PREDICT=1 ;;
    --file)          FILE_ARG="${2:?--file needs a PATH}"; shift ;;
    -o|--output-dir) CLI_OUTDIR="${2:?--output-dir needs a DIR}"; shift ;;
    -p|--priority)   CLI_PRIORITY="${2:?--priority needs a NUM}"; shift ;;
    -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 0 ;;
    -*)              die "unknown option: $1 (try --help)" ;;
    *)
      [ -z "$CLI_IFACE" ] || die "unexpected arg: $1 (iface already set to $CLI_IFACE)"
      CLI_IFACE="$1" ;;
  esac
  shift
done

# source profile (debinst-kexec-style) before resolving: --file > env > default;
# CLI flags (-o/-p/positional) still win (captured above, applied below).
if [ -n "$FILE_ARG" ]; then
  [ -f "$FILE_ARG" ] || die "--file not found: $FILE_ARG"
  # validate in a subshell first so a broken profile becomes a JSON error
  # instead of an uncaught abort. (Values with spaces MUST be quoted, e.g.
  # DNS="a b" — same shell-sourceable shape as debinst-kexec's profiles.)
  if ! ( set -e; . "$FILE_ARG" ) >/dev/null 2>&1; then
    die "--file '$FILE_ARG' failed to source (check shell syntax; quote multi-word values)"
  fi
  # shellcheck source=/dev/null
  . "$FILE_ARG"
fi

OUTDIR="${CLI_OUTDIR:-${OUTDIR:-/etc/systemd/network}}"
PRIORITY="${CLI_PRIORITY:-${PRIORITY:-10}}"
IFACE="${CLI_IFACE:-${IFACE:-}}"
DNS_ENV="${DNS:-}"; DNS6_ENV="${DNS6:-}"

# capture env scalars BEFORE array shadowing below
ADDRS=();  ADDRS6=()
GATEWAY="${GATEWAY:-}"; GATEWAY6="${GATEWAY6:-}"
ROUTES=(); ROUTES6=()
DNS=(); DNS_SOURCE=""

# --- resolve the kernel iface name (gather may auto-detect) ------------------
IFACE_KERNEL="${IFACE:-}"
NAME_SOURCE="given"
if [ "$MODE" = gather ]; then
  command -v ip >/dev/null 2>&1 || die "iproute2 'ip' not found (use render mode)"
  if [ -z "$IFACE_KERNEL" ]; then
    IFACE_KERNEL="$(ip -o -4 route show default 2>/dev/null | sed -n 's/.* via \([^ ]*\) dev \([^ ]*\).*/\2/p' | head -1)"
    # the dev-based form is more reliable; fall back to the simple field
    if [ -z "$IFACE_KERNEL" ]; then
      IFACE_KERNEL="$(ip -o -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')"
    fi
    [ -n "$IFACE_KERNEL" ] || die "could not determine iface (no default route); pass an iface name"
    NAME_SOURCE="kernel-default-route"
  fi
fi
IFACE_MATCH="$IFACE_KERNEL"

# --- predict name (soft) -----------------------------------------------------
if [ "$PREDICT" = 1 ]; then
  if [ -z "$IFACE_KERNEL" ]; then
    PROBLEMS+=("predict-name: no iface to probe; skipped")
  elif predicted="$(predict_udev_name "$IFACE_KERNEL")" && [ -n "$predicted" ]; then
    IFACE_MATCH="$predicted"; NAME_SOURCE="udev(net_id)"
  else
    PROBLEMS+=("predict-name: udevadm net_id unavailable or no predictable name for '$IFACE_KERNEL'; kept it")
  fi
fi

# --- gather / render data ----------------------------------------------------
if [ "$MODE" = gather ]; then
  while read -r a; do
    case "$a" in "" | 127.*) continue ;; esac
    ADDRS+=("$a")
  done < <(ip -o -4 addr show dev "$IFACE_KERNEL" 2>/dev/null | awk '{print $4}')
  [ "${#ADDRS[@]}" -gt 0 ] || die "no IPv4 address on $IFACE_KERNEL"
  GATEWAY="$(ip -o -4 route show default dev "$IFACE_KERNEL" 2>/dev/null | sed -n 's/.* via \([^ ]*\).*/\1/p' | head -1)"
  while read -r line; do
    case "$line" in "" | default*) continue ;; *" via "*) ;; *) continue ;; esac
    dst="${line%% *}"
    via="$(printf '%s' "$line" | sed -n 's/.* via \([^ ]*\).*/\1/p')"
    [ -n "$dst" ] && [ -n "$via" ] && ROUTES+=("$dst $via")
  done < <(ip -o -4 route show dev "$IFACE_KERNEL" 2>/dev/null)
  # v6: keep global addresses (drop fe80::/64 link-local); gateway often is fe80::
  while read -r a; do
    case "$a" in "" | fe80::* | ::1/*) continue ;; esac
    ADDRS6+=("$a")
  done < <(ip -o -6 addr show dev "$IFACE_KERNEL" 2>/dev/null | awk '{print $4}')
  GATEWAY6="$(ip -o -6 route show default dev "$IFACE_KERNEL" 2>/dev/null | sed -n 's/.* via \([^ ]*\).*/\1/p' | head -1)"
  while read -r line; do
    case "$line" in "" | default*) continue ;; *" via "*) ;; *) continue ;; esac
    dst="${line%% *}"
    via="$(printf '%s' "$line" | sed -n 's/.* via \([^ ]*\).*/\1/p')"
    [ -n "$dst" ] && [ -n "$via" ] && ROUTES6+=("$dst $via")
  done < <(ip -o -6 route show dev "$IFACE_KERNEL" 2>/dev/null)
  for r in /etc/resolv.conf /run/systemd/resolve/resolv.conf; do
    [ -r "$r" ] || continue
    while read -r ns; do [ -n "$ns" ] && DNS+=("$ns"); done \
      < <(awk '/^nameserver[[:space:]]/ {print $2}' "$r" | grep -v '^127\.')
    if [ "${#DNS[@]}" -gt 0 ]; then DNS_SOURCE="gathered"; break; fi
  done
else
  [ -n "$IFACE" ] || die "render needs IFACE= (the [Match] Name=)"
  [ -n "${ADDRESS:-}${ADDRESS6:-}" ] || die "render needs ADDRESS (v4) and/or ADDRESS6 (v6); both unset"
  if [ -n "${ADDRESS:-}" ]; then
    if   [ -n "${PREFIX:-}" ];  then pfx="$PREFIX"
    elif [ -n "${NETMASK:-}" ]; then pfx="$(netmask_to_prefix "$NETMASK")"
    else pfx=32; fi
    ADDRS+=("$ADDRESS/$pfx")
  fi
  if [ -n "${ADDRESS6:-}" ]; then ADDRS6+=("$ADDRESS6/${PREFIX6:-64}"); fi
  if [ -n "$DNS_ENV" ];  then read -r -a DNS <<<"$DNS_ENV";  DNS_SOURCE="given"; fi
  if [ -n "$DNS6_ENV" ]; then
    read -r -a _d6 <<<"$DNS6_ENV"; DNS+=("${_d6[@]}"); DNS_SOURCE="given"
  fi
fi

# --- DNS fallback (soft) -----------------------------------------------------
if [ "${#DNS[@]}" -eq 0 ]; then
  DNS=("${FALLBACK_DNS[@]}"); DNS_SOURCE="fallback(opendns+google)"
fi

# --- render the .network file ------------------------------------------------
HAVE_V6=0
if [ "${#ADDRS6[@]}" -gt 0 ] || [ -n "$GATEWAY6" ]; then HAVE_V6=1; fi

mkdir -p "$OUTDIR"
FILE="$OUTDIR/${PRIORITY}-${IFACE_MATCH}.network"
{
  printf '# generated by networkd-static.sh (%s, name=%s) on %s\n' "$MODE" "$NAME_SOURCE" "$(date -u +%FT%TZ 2>/dev/null || date)"
  printf '[Match]\nName=%s\n\n' "$IFACE_MATCH"
  printf '[Network]\n'
  for a in "${ADDRS[@]}";  do printf 'Address=%s\n' "$a"; done
  if [ "${#ADDRS6[@]}" -gt 0 ]; then for a in "${ADDRS6[@]}"; do printf 'Address=%s\n' "$a"; done; fi
  if [ -n "$GATEWAY"  ]; then printf 'Gateway=%s\n' "$GATEWAY";  fi
  if [ -n "$GATEWAY6" ]; then printf 'Gateway=%s\n' "$GATEWAY6"; fi
  if [ "${#DNS[@]}" -gt 0 ]; then for ns in "${DNS[@]}"; do printf 'DNS=%s\n' "$ns"; done; fi
  printf 'DHCP=no\n'
  if [ "$HAVE_V6" = 1 ]; then
    printf '# static ipv6 present -> disable RA/DHCPv6 for determinism\nIPv6AcceptRA=no\n'
  fi
  printf '# keep ipv6 link-local (needed for ND); drop v4 link-local\nLinkLocalAddressing=ipv6\n'
  if [ "${#ROUTES[@]}"  -gt 0 ]; then
    for rt in "${ROUTES[@]}"; do
      dst="${rt%% *}"; via="${rt#* }"
      printf '\n[Route]\nDestination=%s\nGateway=%s\n' "$dst" "$via"
    done
  fi
  if [ "${#ROUTES6[@]}" -gt 0 ]; then
    for rt in "${ROUTES6[@]}"; do
      dst="${rt%% *}"; via="${rt#* }"
      printf '\n[Route]\nDestination=%s\nGateway=%s\n' "$dst" "$via"
    done
  fi
} > "$FILE"

# --- stdout: file path (for $(...)) ------------------------------------------
echo "$FILE"

# --- stderr: single JSON status blob -----------------------------------------
{
  printf '{'
  printf '"ok":%s,' "$([ "${#PROBLEMS[@]}" -eq 0 ] && echo true || echo false)"
  printf '"mode":%s,' "$(json_str "$MODE")"
  printf '"iface_requested":%s,' "$(json_opt "${IFACE:-}")"
  printf '"iface_kernel":%s,' "$(json_opt "$IFACE_KERNEL")"
  printf '"iface_match":%s,' "$(json_str "$IFACE_MATCH")"
  printf '"name_source":%s,' "$(json_str "$NAME_SOURCE")"
  printf '"addrs4":%s,' "$(json_arr "${ADDRS[@]}")"
  printf '"gateway4":%s,' "$(json_opt "$GATEWAY")"
  printf '"addrs6":%s,' "$(json_arr "${ADDRS6[@]}")"
  printf '"gateway6":%s,' "$(json_opt "$GATEWAY6")"
  printf '"routes4":%s,' "$(json_arr "${ROUTES[@]}")"
  printf '"routes6":%s,' "$(json_arr "${ROUTES6[@]}")"
  printf '"dns":%s,' "$(json_arr "${DNS[@]}")"
  printf '"dns_source":%s,' "$(json_str "$DNS_SOURCE")"
  printf '"output":%s,' "$(json_str "$FILE")"
  printf '"problems":%s' "$(json_arr "${PROBLEMS[@]}")"
  printf '}\n'
} >&2
