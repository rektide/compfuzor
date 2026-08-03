#!/bin/bash
# networkd-static.sh — generate systemd-networkd .network files.
#
# WHY this exists: deterministic networkd config — no DHCP dependency where you
# don't want one, and a way to reproduce a box's networking elsewhere. This is
# a GENERIC tool with several uses: configure an installed system, migrate a
# Debian ifupdown box to networkd, bake output into an initrd/UKI, or snapshot
# a live interface to reproduce it statically (the rescue/kexec "same IP" case
# is just one instance). Emits .network files — IPv4 AND IPv6.
#
# (networkd is the daemon; networkctl is just the status query tool. Files
# written here are consumed by systemd-networkd.service.)
#
# MODES
#   RENDER           (default) emit from --file profile / env / positional iface
#   GATHER  (--gather)         read a live interface and reproduce it statically
#   FROM-INTERFACES (--from-interfaces [PATH])
#                              parse a Debian ifupdown /etc/network/interfaces
#                              (or PATH), detect dhcp vs static per iface, and
#                              emit one .network per iface (DHCP= where ifupdown
#                              said dhcp, static Address=/Gateway=/DNS= otherwise).
#
# INPUT (render): --file profile > env vars > positional iface, in that order;
# CLI flags -o/-p always win. Profile = key=value lines (IFACE=/ADDRESS=/...),
# same shape as debinst-kexec's etc/<host>.env files.
#
# USAGE
#   # render from a profile
#   networkd-static.sh --file nasu.net.env
#   # render from env
#   IFACE=eth0 ADDRESS=10.0.0.5 NETMASK=255.255.255.0 GATEWAY=10.0.0.1 networkd-static.sh
#   # snapshot a live interface
#   networkd-static.sh --gather --predict-name -o /mnt/rescue/etc/systemd/network
#   # migrate a Debian ifupdown box to networkd
#   networkd-static.sh --from-interfaces -o /etc/systemd/network
#   networkd-static.sh --from-interfaces /path/to/interfaces -o /tmp/net
#
# RENDER env (v4):  IFACE ADDRESS [PREFIX|NETMASK] GATEWAY DNS
# RENDER env (v6):  ADDRESS6 [PREFIX6] GATEWAY6 DNS6        (PREFIX6 default 64)
# GATHER env:       (none; reads the live iface)
# FROM-INTERFACES:  PATH (default /etc/network/interfaces)
#
# OPTIONS
#   --from-interfaces [PATH]  parse Debian ifupdown interfaces file (multi-iface)
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
#   stdout: the path of each .network file written (one per line; for $(...) use).
#   stderr: a single JSON status object at the end (ok/mode/iface(s)/addrs/gateway/
#           dns/routes/problems). Soft failures collect in "problems" and do NOT
#           stop the run.
#
#   <OUTDIR>/<PRIORITY>-<iface>.network  (iface = predicted name if --predict-name)
#   [Match] Name= + [Network] Address= (v4+v6)/Gateway=(v4+v6)/DNS=/DHCP=<mode>/
#   LinkLocalAddressing=ipv6, plus one [Route] per non-default static route.
#   DHCP=<no|ipv4|ipv6|yes>: render/gather always DHCP=no (static); from-interfaces
#   sets it per-iface from the ifupdown method. .link/.netdev (bridges/bonds/vlans)
#   are NOT emitted. (For NIC-rename resilience without --predict-name, hand-edit
#   [Match] to MACAddress=<hwaddr>.)
#
# DNS: if none is resolved/given, render/gather fall back to OpenDNS + Google
# hardcodes (208.67.222.222 208.67.220.220 8.8.8.8 8.8.4.4). from-interfaces does
# NOT add fallback DNS (respects exactly what interfaces said, including none).
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

# --- the .network writer (shared by all modes) -------------------------------
# Uses globals: IFACE_MATCH, NAME_SOURCE, MODE, ADDRS[], ADDRS6[], GATEWAY,
# GATEWAY6, ROUTES[], ROUTES6[], DNS[], DHCP_MODE, OUTDIR, PRIORITY.
# Writes <OUTDIR>/<PRIORITY>-<IFACE_MATCH>.network and echoes its path.
emit_network() {
  local have_v6=0 file
  if [ "${#ADDRS6[@]}" -gt 0 ] || [ -n "$GATEWAY6" ]; then have_v6=1; fi
  mkdir -p "$OUTDIR"
  file="$OUTDIR/${PRIORITY}-${IFACE_MATCH}.network"
  {
    printf '# generated by networkd-static.sh (%s, name=%s) on %s\n' "$MODE" "$NAME_SOURCE" "$(date -u +%FT%TZ 2>/dev/null || date)"
    printf '[Match]\nName=%s\n\n' "$IFACE_MATCH"
    printf '[Network]\n'
    local a ns rt
    for a in "${ADDRS[@]}";  do printf 'Address=%s\n' "$a"; done
    if [ "${#ADDRS6[@]}" -gt 0 ]; then for a in "${ADDRS6[@]}"; do printf 'Address=%s\n' "$a"; done; fi
    if [ -n "$GATEWAY"  ]; then printf 'Gateway=%s\n' "$GATEWAY";  fi
    if [ -n "$GATEWAY6" ]; then printf 'Gateway=%s\n' "$GATEWAY6"; fi
    if [ "${#DNS[@]}" -gt 0 ]; then for ns in "${DNS[@]}"; do printf 'DNS=%s\n' "$ns"; done; fi
    printf 'DHCP=%s\n' "$DHCP_MODE"
    if [ "$have_v6" = 1 ]; then
      printf '# static ipv6 present -> disable RA/DHCPv6 for determinism\nIPv6AcceptRA=no\n'
    fi
    printf '# keep ipv6 link-local (needed for ND); drop v4 link-local\nLinkLocalAddressing=ipv6\n'
    if [ "${#ROUTES[@]}"  -gt 0 ]; then
      for rt in "${ROUTES[@]}"; do
        printf '\n[Route]\nDestination=%s\nGateway=%s\n' "${rt%% *}" "${rt#* }"
      done
    fi
    if [ "${#ROUTES6[@]}" -gt 0 ]; then
      for rt in "${ROUTES6[@]}"; do
        printf '\n[Route]\nDestination=%s\nGateway=%s\n' "${rt%% *}" "${rt#* }"
      done
    fi
  } > "$file"
  echo "$file"
}

# Emit the per-IFACE JSON status blob to stderr (shared by render/gather).
emit_status() {
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
    printf '"output":%s,' "$(json_str "$OUTDIR/${PRIORITY}-${IFACE_MATCH}.network")"
    printf '"problems":%s' "$(json_arr "${PROBLEMS[@]}")"
    printf '}\n'
  } >&2
}

# Apply --predict-name to the resolved kernel iface (soft): ask udev net_id
# what it would name IFACE_KERNEL afresh and use that for [Match] Name= + file.
resolve_predict_name() {
  if [ "$PREDICT" = 1 ]; then
    if [ -z "$IFACE_KERNEL" ]; then
      PROBLEMS+=("predict-name: no iface to probe; skipped")
    elif predicted="$(predict_udev_name "$IFACE_KERNEL")" && [ -n "$predicted" ]; then
      IFACE_MATCH="$predicted"; NAME_SOURCE="udev(net_id)"
    else
      PROBLEMS+=("predict-name: udevadm net_id unavailable or no predictable name for '$IFACE_KERNEL'; kept it")
    fi
  fi
}

# --- arg parse ---------------------------------------------------------------
MODE=render
CLI_IFACE=""; CLI_OUTDIR=""; CLI_PRIORITY=""; FILE_ARG=""; FROM_FILE=""; PREDICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --from-interfaces)          MODE=from-interfaces; [ "${2:-}" != "" ] && ! [[ "$2" =~ ^- ]] && { FROM_FILE="$2"; shift; } ;;
    --render)                   MODE=render ;;
    --gather)                   MODE=gather ;;
    --predict-name)             PREDICT=1 ;;
    --file)                     FILE_ARG="${2:?--file needs a PATH}"; shift ;;
    -o|--output-dir)            CLI_OUTDIR="${2:?--output-dir needs a DIR}"; shift ;;
    -p|--priority)              CLI_PRIORITY="${2:?--priority needs a NUM}"; shift ;;
    -h|--help)                  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 0 ;;
    -*)                         die "unknown option: $1 (try --help)" ;;
    *)
      [ -z "$CLI_IFACE" ] || die "unexpected arg: $1 (iface already set to $CLI_IFACE)"
      CLI_IFACE="$1" ;;
  esac
  shift
done

# OUTDIR/PRIORITY resolve once (used by every mode).
OUTDIR="${CLI_OUTDIR:-${OUTDIR:-/etc/systemd/network}}"
PRIORITY="${CLI_PRIORITY:-${PRIORITY:-10}}"
DHCP_MODE="${DHCP_MODE:-no}"

# ===========================================================================
# MODE: from-interfaces  — parse Debian ifupdown, emit one .network per iface
# ===========================================================================
run_from_interfaces() {
  local file="${FROM_FILE:-/etc/network/interfaces}"
  [ -f "$file" ] || die "from-interfaces: file not found: $file"

  # per-iface accumulators (associative, keyed by iface name)
  declare -A v4m v6m v4a v4n v6a v4g v6g dns
  local order=()   # iface names in first-seen order
  local cur="" fam=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"            # strip "#" comments
    set -- $line                  # word-split (drops leading/trailing ws)
    [ $# -eq 0 ] && continue
    case "$1" in
      iface)
        cur="$2"; fam="$3"; local m="${4:-none}"
        # skip loopback + unknown families
        if [ "$m" = "loopback" ] || ! [[ "$fam" =~ ^(inet|inet6)$ ]]; then cur=""; continue; fi
        case "$fam" in
          inet)  v4m[$cur]="$m" ;;
          inet6) v6m[$cur]="$m" ;;
        esac
        # ordered unique append
        local _seen=0 x; for x in "${order[@]+"${order[@]}"}"; do [ "$x" = "$cur" ] && _seen=1; done
        [ $_seen = 0 ] && order+=("$cur")
        ;;
      address)
        [ -n "$cur" ] || continue
        case "$fam" in
          inet)  v4a[$cur]="${v4a[$cur]:+${v4a[$cur]} }$2" ;;
          inet6) v6a[$cur]="${v6a[$cur]:+${v6a[$cur]} }$2" ;;
        esac ;;
      netmask)
        [ -n "$cur" ] && [ "$fam" = inet ] && v4n[$cur]="$2" ;;
      gateway)
        [ -n "$cur" ] || continue
        case "$fam" in
          inet)  v4g[$cur]="$2" ;;
          inet6) v6g[$cur]="$2" ;;
        esac ;;
      dns-nameservers)
        [ -n "$cur" ] && dns[$cur]="${dns[$cur]:+${dns[$cur]} }${*:2}" ;;
      auto|allow-*|no-auto|source|source-directory|mapping|vlan-*|bond-*|bridge*) : ;;  # ignored
    esac
  done < "$file"

  [ "${#order[@]}" -gt 0 ] || die "from-interfaces: no iface stanzas found in $file"

  NAME_SOURCE="from-interfaces"
  IFACE_KERNEL=""
  local written=() ifc a pfx
  for ifc in "${order[@]}"; do
    # reset per-iface globals consumed by emit_network
    IFACE="$ifc"; IFACE_MATCH="$ifc"
    ADDRS=(); ADDRS6=(); GATEWAY=""; GATEWAY6=""; ROUTES=(); ROUTES6=(); DNS=()
    DNS_SOURCE="from-interfaces"

    # DHCP= combines v4/v6 method (dhcp on each family)
    local v4d=0 v6d=0
    [ "${v4m[$ifc]:-}" = "dhcp" ] && v4d=1
    [ "${v6m[$ifc]:-}" = "dhcp" ] && v6d=1
    if   [ $v4d = 1 ] && [ $v6d = 1 ]; then DHCP_MODE=yes
    elif [ $v4d = 1 ]; then DHCP_MODE=ipv4
    elif [ $v6d = 1 ]; then DHCP_MODE=ipv6
    else DHCP_MODE=no
    fi

    # static v4: address(es) + optional netmask->prefix (address may already be CIDR)
    if [ -n "${v4a[$ifc]:-}" ]; then
      for a in ${v4a[$ifc]}; do
        case "$a" in
          */*) ADDRS+=("$a") ;;
          *)   pfx=32; [ -n "${v4n[$ifc]:-}" ] && pfx="$(netmask_to_prefix "${v4n[$ifc]}")"
               ADDRS+=("$a/$pfx") ;;
        esac
      done
    fi
    [ -n "${v4g[$ifc]:-}" ] && GATEWAY="${v4g[$ifc]}"

    # static v6: address (assume CIDR, default /64)
    if [ -n "${v6a[$ifc]:-}" ]; then
      for a in ${v6a[$ifc]}; do
        case "$a" in */*) ADDRS6+=("$a") ;; *) ADDRS6+=("$a/64") ;; esac
      done
    fi
    [ -n "${v6g[$ifc]:-}" ] && GATEWAY6="${v6g[$ifc]}"

    if [ -n "${dns[$ifc]:-}" ]; then read -r -a DNS <<<"${dns[$ifc]}"; fi

    emit_network && written+=("$ifc")
  done

  # stderr: summary JSON
  {
    printf '{'
    printf '"ok":%s,' "$([ ${#written[@]} -gt 0 ] && echo true || echo false)"
    printf '"mode":%s,' "$(json_str "$MODE")"
    printf '"source":%s,' "$(json_str "$file")"
    printf '"ifaces":%s,' "$(json_arr "${written[@]}")"
    printf '"problems":%s' "$(json_arr "${PROBLEMS[@]}")"
    printf '}\n'
  } >&2
  exit 0
}

# ===========================================================================
# MODE: render — build .network from --file profile / env (single iface)
# ===========================================================================
run_render() {
  local pfx
  # source profile (debinst-kexec-style): --file > env > default; -o/-p captured above.
  if [ -n "$FILE_ARG" ]; then
    [ -f "$FILE_ARG" ] || die "--file not found: $FILE_ARG"
    # validate in a subshell so a broken profile becomes a JSON error instead of
    # an uncaught abort. Multi-word values MUST be quoted (e.g. DNS="a b").
    if ! ( set -e; . "$FILE_ARG" ) >/dev/null 2>&1; then
      die "--file '$FILE_ARG' failed to source (check shell syntax; quote multi-word values)"
    fi
    # shellcheck source=/dev/null
    . "$FILE_ARG"
  fi
  IFACE="${CLI_IFACE:-${IFACE:-}}"
  [ -n "$IFACE" ] || die "render needs IFACE= (the [Match] Name=)"
  [ -n "${ADDRESS:-}${ADDRESS6:-}" ] || die "render needs ADDRESS (v4) and/or ADDRESS6 (v6); both unset"
  IFACE_KERNEL="$IFACE"; IFACE_MATCH="$IFACE"; NAME_SOURCE="given"
  ADDRS=(); ADDRS6=(); GATEWAY="${GATEWAY:-}"; GATEWAY6="${GATEWAY6:-}"; ROUTES=(); ROUTES6=(); DNS=(); DNS_SOURCE=""
  if [ -n "${ADDRESS:-}" ]; then
    if   [ -n "${PREFIX:-}" ];  then pfx="$PREFIX"
    elif [ -n "${NETMASK:-}" ]; then pfx="$(netmask_to_prefix "$NETMASK")"
    else pfx=32; fi
    ADDRS+=("$ADDRESS/$pfx")
  fi
  if [ -n "${ADDRESS6:-}" ]; then ADDRS6+=("$ADDRESS6/${PREFIX6:-64}"); fi
  if [ -n "${DNS:-}" ];  then read -r -a DNS <<<"$DNS";  DNS_SOURCE="given"; fi
  if [ -n "${DNS6:-}" ]; then read -r -a _d6 <<<"$DNS6"; DNS+=("${_d6[@]}"); DNS_SOURCE="given"; fi
  resolve_predict_name
  if [ "${#DNS[@]}" -eq 0 ]; then DNS=("${FALLBACK_DNS[@]}"); DNS_SOURCE="fallback(opendns+google)"; fi
  emit_network >/dev/null
  emit_status
}

# ===========================================================================
# MODE: gather — snapshot a live interface to a static .network (single iface)
# ===========================================================================
run_gather() {
  command -v ip >/dev/null 2>&1 || die "iproute2 'ip' not found (use render mode)"
  IFACE="${CLI_IFACE:-${IFACE:-}}"
  IFACE_KERNEL="$IFACE"; IFACE_MATCH="$IFACE"; NAME_SOURCE="given"
  if [ -z "$IFACE_KERNEL" ]; then
    # auto-detect from the default route (sed form, then awk fallback)
    IFACE_KERNEL="$(ip -o -4 route show default 2>/dev/null | sed -n 's/.* via \([^ ]*\) dev \([^ ]*\).*/\2/p' | head -1)"
    if [ -z "$IFACE_KERNEL" ]; then
      IFACE_KERNEL="$(ip -o -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')"
    fi
    [ -n "$IFACE_KERNEL" ] || die "could not determine iface (no default route); pass an iface name"
    NAME_SOURCE="kernel-default-route"; IFACE_MATCH="$IFACE_KERNEL"
  fi
  ADDRS=(); ADDRS6=(); GATEWAY=""; GATEWAY6=""; ROUTES=(); ROUTES6=(); DNS=(); DNS_SOURCE=""
  local a line dst via r
  while read -r a; do case "$a" in "" | 127.*) continue ;; esac; ADDRS+=("$a"); done \
    < <(ip -o -4 addr show dev "$IFACE_KERNEL" 2>/dev/null | awk '{print $4}')
  [ "${#ADDRS[@]}" -gt 0 ] || die "no IPv4 address on $IFACE_KERNEL"
  GATEWAY="$(ip -o -4 route show default dev "$IFACE_KERNEL" 2>/dev/null | sed -n 's/.* via \([^ ]*\).*/\1/p' | head -1)"
  while read -r line; do
    case "$line" in "" | default*) continue ;; *" via "*) ;; *) continue ;; esac
    dst="${line%% *}"; via="$(printf '%s' "$line" | sed -n 's/.* via \([^ ]*\).*/\1/p')"
    [ -n "$dst" ] && [ -n "$via" ] && ROUTES+=("$dst $via")
  done < <(ip -o -4 route show dev "$IFACE_KERNEL" 2>/dev/null)
  # v6: keep global addresses (drop fe80::/64 link-local); gateway often is fe80::
  while read -r a; do case "$a" in "" | fe80::* | ::1/*) continue ;; esac; ADDRS6+=("$a"); done \
    < <(ip -o -6 addr show dev "$IFACE_KERNEL" 2>/dev/null | awk '{print $4}')
  GATEWAY6="$(ip -o -6 route show default dev "$IFACE_KERNEL" 2>/dev/null | sed -n 's/.* via \([^ ]*\).*/\1/p' | head -1)"
  while read -r line; do
    case "$line" in "" | default*) continue ;; *" via "*) ;; *) continue ;; esac
    dst="${line%% *}"; via="$(printf '%s' "$line" | sed -n 's/.* via \([^ ]*\).*/\1/p')"
    [ -n "$dst" ] && [ -n "$via" ] && ROUTES6+=("$dst $via")
  done < <(ip -o -6 route show dev "$IFACE_KERNEL" 2>/dev/null)
  for r in /etc/resolv.conf /run/systemd/resolve/resolv.conf; do
    [ -r "$r" ] || continue
    while read -r ns; do [ -n "$ns" ] && DNS+=("$ns"); done \
      < <(awk '/^nameserver[[:space:]]/ {print $2}' "$r" | grep -v '^127\.')
    if [ "${#DNS[@]}" -gt 0 ]; then DNS_SOURCE="gathered"; break; fi
  done
  resolve_predict_name
  if [ "${#DNS[@]}" -eq 0 ]; then DNS=("${FALLBACK_DNS[@]}"); DNS_SOURCE="fallback(opendns+google)"; fi
  emit_network >/dev/null
  emit_status
}

# ===========================================================================
# dispatch
# ===========================================================================
case "$MODE" in
  from-interfaces) run_from_interfaces ;;   # exits with its own summary
  gather)          run_gather ;;
  render|*)        run_render ;;
esac
