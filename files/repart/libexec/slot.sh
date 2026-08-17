#!/bin/bash
set -euo pipefail

die() { printf 'repart slot: error: %s\n' "$*" >&2; exit 2; }
note() { printf 'repart slot: %s\n' "$*" >&2; }
os_prefix="${REPART_OS_PREFIX:-/os/superbfowle}"
home_prefix="${REPART_HOME_PREFIX:-/home/superbfowle}"
arch="${REPART_ARCH:-$(case "$(uname -m)" in x86_64) echo amd64 ;; aarch64) echo arm64 ;; *) uname -m ;; esac)}"
valid_date() { case "$1" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "bad date '$1' (want YYYYMMDD)" ;; esac; }
slot_path() { if [ "$1" = home ]; then printf '%s/%s' "$home_prefix" "$2"; else printf '%s/%s/%s' "$os_prefix" "$arch" "$2"; fi; }
list_os() {
  btrfs subvolume list "$1" | awk -v p="${os_prefix#/}/$arch/" '
    index($NF,p)==1 { d=substr($NF,length(p)+1); if (length(d)==8 && d !~ /[^0-9]/) print "/"$NF }
  '
}

command="${1:-}"; shift || true
case "$command" in
  path)
    kind=os; if [ "${1:-}" = --home ]; then kind=home; shift; fi
    date_value="${1:-$(date +%Y%m%d)}"; [ $# -le 1 ] || die "too many path arguments"; valid_date "$date_value"
    slot_path "$kind" "$date_value"; printf '\n'
    ;;
  show)
    [ $# -eq 1 ] || die "usage: repart slot show MOUNT"; mountpoint="$1"; [ -d "$mountpoint" ] || die "not a directory: $mountpoint"
    default="$(btrfs subvolume get-default "$mountpoint" 2>/dev/null | sed -n 's/.* path /\//p')"; [ -n "$default" ] || default=/
    printf 'kind\tdate\tpath\tdefault\n'
    while IFS= read -r path; do
      date_value="${path##*/}"; valid_date "$date_value"
      marker=false; [ "$path" != "$default" ] || marker=true
      printf 'os\t%s\t%s\t%s\n' "$date_value" "$path" "$marker"
    done < <(list_os "$mountpoint" | sort -t/ -k5,5)
    while IFS= read -r path; do
      date_value="${path##*/}"; valid_date "$date_value"
      printf 'home\t%s\t%s\tfalse\n' "$date_value" "$path"
    done < <(btrfs subvolume list "$mountpoint" | awk -v p="${home_prefix#/}/" '
      index($NF,p)==1 { d=substr($NF,length(p)+1); if (length(d)==8 && d !~ /[^0-9]/) print "/"$NF }
    ' | sort -t/ -k4,4)
    ;;
  set)
    [ $# -eq 2 ] || die "usage: repart slot set MOUNT DATE|PATH|latest"; mountpoint="$1"; selector="$2"; [ -d "$mountpoint" ] || die "not a directory: $mountpoint"
    case "$selector" in
      latest) target="$(list_os "$mountpoint" | sort | tail -1)"; [ -n "$target" ] || die "no known OS slots" ;;
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) valid_date "$selector"; target="$(slot_path os "$selector")" ;;
      /*) target="$selector" ;;
      *) die "selector must be DATE, absolute PATH, or latest" ;;
    esac
    known=false; while IFS= read -r path; do [ "$path" != "$target" ] || known=true; done < <(list_os "$mountpoint")
    $known || die "not an exact known OS slot path: $target"
    id="$(btrfs subvolume list "$mountpoint" | awk -v p="${target#/}" '$NF==p {print $2; exit}')"
    btrfs subvolume set-default "$id" "$mountpoint"
    note "default slot set to $target (id $id)"
    ;;
  *) die "usage: repart slot {path|show|set} ..." ;;
esac
