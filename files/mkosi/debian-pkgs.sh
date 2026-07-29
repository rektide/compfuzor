#!/bin/bash
# debian-pkgs.sh — screen Debian package tiers (essential / recommends / suggests)
# to stdout, for reviewing what an image build would pull in.
#
# Debian tiers:
#   essential  : dpkg "Essential: yes" packages (the bare minimum; never removed)
#   recommends : Recommends of a given package set (on by default with apt)
#   suggests   : Suggests ("bonus"; off by default) of a given package set
#
# USAGE
#   debian-pkgs.sh essential                         # installed essential set
#   debian-pkgs.sh recommends [pkg ...]              # Recommends of pkgs
#   debian-pkgs.sh suggests   [pkg ...]              # Suggests of pkgs (bonus)
#   debian-pkgs.sh all        [pkg ...]              # all three tiers, labelled
#
# If no pkgs are given for recommends/suggests, reads $DIR/etc/pkgs.txt (the
# compfuzor image package list) if present, else errors.
#
# No root needed (uses dpkg-query + apt-cache against existing apt metadata).

set -euo pipefail

die() { printf 'debian-pkgs: %s\n' "$*" >&2; exit 1; }

MODE="${1:-}"; shift || true
[ -n "$MODE" ] || die "usage: $0 essential|recommends|suggests|all [pkg ...]"

load_pkgs() {
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; return; fi
  # etc/pkgs.txt relative to the compfuzor DIR (script lives in <DIR>/bin/).
  local dir="${DIR:-$(realpath -m "$(dirname "$(readlink -f "$0")")/..")}"
  local f="$dir/etc/pkgs.txt"
  [ -f "$f" ] || die "no packages given and $f not found; pass pkgs as args"
  grep -vE '^\s*(#|$)' "$f"
}

list_essential() {
  dpkg-query -W -f='${binary:Package}\t${Essential}\n' 2>/dev/null \
    | awk -F'\t' '$2=="yes"{print $1}' | sort -u
}

# apt-cache depends prints "  Recommends: name" (with optional leading | or <ver>);
# extract the bare package name.
list_depfield() {
  local field="$1"; shift
  apt-cache depends "$@" 2>/dev/null \
    | awk -v f="$field" '$0 ~ f {n=$NF; gsub(/[<>=|]/,"",n); if(n!="") print n}' \
    | sort -u
}

case "$MODE" in
  essential)  list_essential ;;
  recommends) list_depfield "Recommends:" $(load_pkgs "$@") ;;
  suggests)   list_depfield "Suggests:"   $(load_pkgs "$@") ;;
  all)
    echo "### essential ($(list_essential | wc -l))"
    list_essential
    pkgs=$(load_pkgs "$@")
    echo; echo "### recommends ($(list_depfield "Recommends:" $pkgs | wc -l))"
    list_depfield "Recommends:" $pkgs
    echo; echo "### suggests/bonus ($(list_depfield "Suggests:" $pkgs | wc -l))"
    list_depfield "Suggests:" $pkgs
    ;;
  *) die "unknown mode '$MODE'; try essential|recommends|suggests|all" ;;
esac
