#!/bin/bash
set -euo pipefail

die() { printf 'repart profile: error: %s\n' "$*" >&2; exit 2; }
note() { printf 'repart profile: %s\n' "$*" >&2; }

[ "${1:-}" = render ] || die "usage: repart profile render --base DIR [--overlay DIR...] [--date YYYYMMDD] [--arch ARCH] [--swap SIZE] [--set NAME=VALUE...]"
shift
base=""; date_value="$(date +%Y%m%d)"; swap=4G
arch="$(case "$(uname -m)" in x86_64) echo amd64 ;; aarch64) echo arm64 ;; *) uname -m ;; esac)"
overlays=(); names=(DATE ARCH SWAP); values=("$date_value" "$arch" "$swap")
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:?--base needs DIR}"; shift 2 ;;
    --overlay) overlays+=("${2:?--overlay needs DIR}"); shift 2 ;;
    --date) values[0]="${2:?--date needs YYYYMMDD}"; shift 2 ;;
    --arch) values[1]="${2:?--arch needs ARCH}"; shift 2 ;;
    --swap) values[2]="${2:?--swap needs SIZE}"; shift 2 ;;
    --set)
      pair="${2:?--set needs NAME=VALUE}"; name="${pair%%=*}"
      [ "$pair" != "$name" ] || die "--set needs NAME=VALUE"
      case "$name" in ''|*[!A-Z0-9_]*|[0-9_]*) die "invalid token name: $name" ;; esac
      replaced=false
      for i in "${!names[@]}"; do
        if [ "${names[$i]}" = "$name" ]; then values[$i]="${pair#*=}"; replaced=true; break; fi
      done
      if ! $replaced; then names+=("$name"); values+=("${pair#*=}"); fi
      shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done
[ -n "$base" ] && [ -d "$base" ] || die "--base must name a directory"
case "${values[0]}" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "bad date '${values[0]}' (want YYYYMMDD)" ;; esac
for overlay in "${overlays[@]}"; do [ -d "$overlay" ] || die "overlay is not a directory: $overlay"; done

scratch="${REPART_SCRATCH:-/var/tmp}"
mkdir -p "$scratch"
tree="$(mktemp -d "$scratch/repart-profile.XXXXXX")"
trap 'rm -rf "$tree"' ERR INT TERM
cp -a "$base"/. "$tree"/
for overlay in "${overlays[@]}"; do cp -a "$overlay"/. "$tree"/; done

sed_args=()
for i in "${!names[@]}"; do
  escaped="${values[$i]//\\/\\\\}"; escaped="${escaped//|/\\|}"; escaped="${escaped//&/\\&}"
  sed_args+=(-e "s|@${names[$i]}@|$escaped|g")
done
while IFS= read -r -d '' file; do sed -i "${sed_args[@]}" "$file"; done < <(grep -rIlZ '@[A-Z][A-Z0-9_]*@' "$tree" 2>/dev/null || true)
unresolved="$(grep -rIlnE '@[A-Z][A-Z0-9_]*@' "$tree" 2>/dev/null || true)"
if [ -n "$unresolved" ]; then printf '%s\n' "$unresolved" >&2; die "unresolved uppercase profile tokens"; fi
trap - ERR INT TERM
tree="$(realpath "$tree")"
note "rendered profile at $tree; caller owns this tree"
printf '%s\n' "$tree"
