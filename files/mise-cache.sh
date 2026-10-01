# mise-cache.sh — inventory and selective clearing of the caches that mise
# and the tools it manages keep on this machine: mise's own metadata cache,
# download staging and installs, plus the per-ecosystem caches those tools
# maintain (npm, pnpm, yarn, bun, deno, cargo, go, gradle, maven, pip, uv,
# nuget, prettier).
#
# Commands:
#   status [--fast]    per-area sizes + resolved paths, plus a `mise prune`
#                      candidate list. --fast skips du (sizes print as "-").
#   list               every catalog area with presence and actions
#   gc AREAS...|--all  safe reclaim commands (mise cache prune, pnpm store
#                      prune, uv cache prune, mise prune --tools)
#   clear AREAS...|--all
#                      wipe areas: the native tool command when it is on
#                      PATH, else rm -rf of the resolved roots
#
# gc/clear accept --dry-run (print the actions only) and -a/--all (every
# present area that has that action). Areas absent on this machine are
# skipped. `clear` never runs without an explicit selection.
#
# Registered in STATUSES as `mise-cache.sh status --fast` so the aggregate
# status.sh stays quick; invoke `mise-cache.sh status` directly for real
# sizes — a full du across every area can take minutes on a warm machine.
#
# Areas are rendered from the playbook's mise_cache_areas var, fields:
#   name|desc|paths (space-joined)|query|fallback|gc|clear|expand
# `query` asks the tool itself for its root (pnpm store path, go env
# GOMODCACHE, npm config get cache, mise cache path); `fallback` applies when
# the tool is not on PATH. Authored path strings are runtime-expanded (they
# use $HOME and ${XDG_CACHE_HOME:-...} forms); query output is used verbatim
# and never re-expanded. `expand` areas report one-level child sizes instead
# of only an aggregate (mise installs, rustup toolchains). `clear` is a
# native command, the literal `rm`, or `none` for visibility-only areas.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.
{% if TYPE == 'mise2' %}
# mise2: route mise invocations through this deployment's isolated config
# root. Cache and data roots stay shared with the mise deployment until
# MISE_CACHE_DIR/MISE_DATA_DIR are redirected as well.
MISE_PREFIX="MISE_CONFIG_DIR={{ '${' }}MISE2_CONFIG_DIR:-{{mise2_config_dir}}} "
{% else %}
MISE_PREFIX=""
{% endif %}
CACHE_AREAS=(
{% for a in mise_cache_areas | default([]) %}  '{{ a['name'] }}|{{ a['desc'] }}|{{ a['paths'] | default([]) | join(" ") }}|{{ a['query'] | default("") }}|{{ a['fallback'] | default("") }}|{{ a['gc'] | default("") }}|{{ a['clear'] | default("") }}|{{ 1 if a['expand'] | default(False) | bool else 0 }}'
{% endfor %})

{% raw %}
usage() {
  cat >&2 <<EOF
usage: mise-cache.sh status [--fast]
       mise-cache.sh list
       mise-cache.sh gc    AREAS...|--all [--dry-run]
       mise-cache.sh clear AREAS...|--all [--dry-run]
areas: ${A_NAME[*]:-none}
EOF
}

# Expand one authored catalog path string ($VAR, ${VAR:-default}, ~). The
# catalog is rendered from playbook vars -- the same trust level as this
# script's own body -- so a guarded eval is safe here. Query output never
# passes through this function.
expand_path() {
  local raw="$1"
  [ -n "$raw" ] || return 0
  case "$raw" in
    *'"'*|*'`'*|'$('*)
      printf 'mise-cache: refusing suspicious path string: %s\n' "$raw" >&2
      return 1 ;;
    '~') printf '%s\n' "$HOME"; return 0 ;;
    '~/'*) raw="$HOME/${raw#~/}" ;;
  esac
  eval "printf '%s\n' \"${raw}\""
}

# Prefix mise invocations with this deployment's config root (mise2 only).
wrap_cmd() {
  case "$1" in
    mise|mise\ *) printf '%s%s' "$MISE_PREFIX" "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

A_NAME=(); A_DESC=(); A_PATHS=(); A_QUERY=(); A_FALLBACK=(); A_GC=(); A_CLEAR=(); A_EXPAND=()
A_CANDS=(); A_PRESENT=(); A_KB=(); A_CHILDREN=()
for _line in "${CACHE_AREAS[@]}"; do
  IFS='|' read -r _n _d _p _q _f _g _c _e <<< "$_line"
  A_NAME+=("$_n"); A_DESC+=("$_d"); A_PATHS+=("$_p"); A_QUERY+=("$_q")
  A_FALLBACK+=("$_f"); A_GC+=("$_g"); A_CLEAR+=("$_c"); A_EXPAND+=("$_e")
done

# resolve_area I -- print the candidate roots for area I: the query result
# when its tool answers, else the expanded fallback (an unavailable tool and
# an empty/failing query both fall back), plus the expanded static paths.
resolve_area() {
  local i="$1" _q _r _p
  _q="${A_QUERY[$i]}"
  if [ -n "$_q" ]; then
    _r=""
    if command -v "${_q%% *}" >/dev/null 2>&1; then
      _r="$(sh -c "$(wrap_cmd "$_q")" 2>/dev/null | tail -n 1 || true)"
      _r="${_r%$'\r'}"
    fi
    if [ -n "$_r" ]; then
      printf '%s\n' "$_r"
    else
      expand_path "${A_FALLBACK[$i]}" || true
    fi
  fi
  # Static paths are space-joined in the catalog (authored paths never
  # contain spaces; splitting on the default IFS keeps ${VAR:-default}
  # forms intact, which ":" would cut apart).
  for _p in ${A_PATHS[$i]}; do
    [ -n "$_p" ] || continue
    expand_path "$_p" || true
  done
}

for _i in "${!A_NAME[@]}"; do
  declare -A _seen=()
  _cands=""
  _present=0
  while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    if [ -z "${_seen[$_c]:-}" ]; then
      _seen[$_c]=1
      _cands+="${_c}"$'\n'
      if [ -e "$_c" ]; then _present=1; fi
    fi
  done < <(resolve_area "$_i")
  A_CANDS[$_i]="$_cands"
  A_PRESENT[$_i]=$_present
  A_KB[$_i]=""
  A_CHILDREN[$_i]=""
done
unset _seen _cands _present _c _i _line _n _d _p _q _f _g _c _e

CMD=""
DRY=0; ALL=0; FAST=0; SELECT=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    status|list|gc|clear)
      if [ -n "$CMD" ]; then
        printf 'mise-cache: only one command may be given\n' >&2; exit 2
      fi
      CMD="$1" ;;
    --dry-run|-n) DRY=1 ;;
    --all|-a) ALL=1 ;;
    --fast) FAST=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'mise-cache: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)
      case "$CMD" in
        gc|clear) SELECT+=("$1") ;;
        *) printf 'mise-cache: unexpected argument: %s\n' "$1" >&2; exit 2 ;;
      esac ;;
  esac
  shift
done
[ -n "$CMD" ] || { usage; exit 2; }

human() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --format='%.1f' -- "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

run_native() {
  local c
  c="$(wrap_cmd "$1")"
  if [ "$DRY" = 1 ]; then
    printf '  [dry-run] %s\n' "$c"
    return 0
  fi
  if ! command -v "${1%% *}" >/dev/null 2>&1; then
    printf '  %s is not on PATH\n' "${1%% *}" >&2
    return 1
  fi
  printf '  running: %s\n' "$c"
  sh -c "$c"
}

rm_paths() {
  local i="$1" p rc=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || continue
    case "$p" in
      /|"$HOME") printf '  refusing to remove %s\n' "$p" >&2; rc=1; continue ;;
    esac
    if [ "$DRY" = 1 ]; then
      printf '  [dry-run] rm -rf %s\n' "$p"
    else
      printf '  rm -rf %s\n' "$p"
      rm -rf -- "$p" || rc=1
    fi
  done <<< "${A_CANDS[$i]}"
  return "$rc"
}

case "$CMD" in
  status|list)
    if [ "$CMD" = status ] && [ "$FAST" != 1 ]; then
      MTMP="$(mktemp -d)"
      trap 'rm -rf -- "$MTMP"' EXIT
      for i in "${!A_NAME[@]}"; do
        [ "${A_PRESENT[$i]}" = 1 ] || continue
        k=0
        while IFS= read -r p; do
          [ -n "$p" ] || continue
          if [ "${A_EXPAND[$i]}" = 1 ]; then
            ( du -sk -- "${p}"/* >"$MTMP/$i.$k" 2>/dev/null || : >"$MTMP/$i.$k" ) &
          else
            ( du -sk -- "$p" >"$MTMP/$i.$k" 2>/dev/null || : >"$MTMP/$i.$k" ) &
          fi
          k=$((k + 1))
        done <<< "${A_CANDS[$i]}"
      done
      wait
      for i in "${!A_NAME[@]}"; do
        [ "${A_PRESENT[$i]}" = 1 ] || continue
        total=0; children=""
        for f in "$MTMP"/$i.*; do
          [ -f "$f" ] || continue
          while IFS=$'\t' read -r kb rest; do
            [ -n "$kb" ] || continue
            case "$kb" in *[!0-9]*) continue ;; esac
            total=$((total + kb))
            if [ "${A_EXPAND[$i]}" = 1 ]; then
              children+="${kb}"$'\t'"${rest}"$'\n'
            fi
          done < "$f"
        done
        A_KB[$i]=$total
        A_CHILDREN[$i]="$children"
      done
    fi
    present=0; absent=()
    for i in "${!A_NAME[@]}"; do
      if [ "${A_PRESENT[$i]}" = 1 ]; then present=$((present + 1)); else absent+=("${A_NAME[$i]}"); fi
    done
    if [ "$CMD" = list ]; then
      printf '%-14s %-7s %-3s %-5s  %s\n' AREA PRESENT GC CLEAR DESCRIPTION
      for i in "${!A_NAME[@]}"; do
        if [ "${A_PRESENT[$i]}" = 1 ]; then st=present; else st=absent; fi
        if [ -n "${A_GC[$i]}" ]; then g=yes; else g=-; fi
        case "${A_CLEAR[$i]}" in
          none|"") c=- ;;
          rm) c=rm ;;
          *) c=cmd ;;
        esac
        printf '%-14s %-7s %-3s %-5s  %s\n' "${A_NAME[$i]}" "$st" "$g" "$c" "${A_DESC[$i]}"
      done
      exit 0
    fi
    printf 'cache areas: %d present, %d absent\n' "$present" "${#absent[@]}"
    if [ "$present" -gt 0 ]; then
      printf '%-14s %9s  %s\n' AREA SIZE PATHS
      grand=0; measured=0
      for i in "${!A_NAME[@]}"; do
        [ "${A_PRESENT[$i]}" = 1 ] || continue
        size="-"
        if [ -n "${A_KB[$i]}" ]; then
          size="$(human $(( ${A_KB[$i]} * 1024 )))"
          grand=$((grand + A_KB[$i])); measured=1
        fi
        joined="${A_CANDS[$i]%$'\n'}"
        printf '%-14s %9s  %s\n' "${A_NAME[$i]}" "$size" "${joined//$'\n'/ }"
        if [ -n "${A_CHILDREN[$i]}" ]; then
          while IFS=$'\t' read -r kb rest; do
            [ -n "$kb" ] || continue
            printf '    %9s  %s\n' "$(human $(( kb * 1024 )))" "$(basename -- "$rest")"
          done <<< "$(printf '%s' "${A_CHILDREN[$i]}" | sort -rn)"
        fi
      done
      if [ "$measured" = 1 ]; then
        printf '%-14s %9s\n' TOTAL "$(human $(( grand * 1024 )))"
      fi
    fi
    if [ "${#absent[@]}" -gt 0 ]; then
      printf 'absent: %s\n' "${absent[*]}"
    fi
    if command -v mise >/dev/null 2>&1; then
      printf '\nmise prune candidates (mise prune --tools):\n'
      # mise prune reports on stderr; merge before filtering, truncate the
      # (sometimes huge) reason to keep the status readable
      _prune="$(sh -c "$(wrap_cmd 'mise prune --dry-run --tools')" 2>&1 \
        | sed -n 's/^mise \(.*\) is prunable: \(.\{0,57\}\).*/  \1: \2.../p' || true)"
      if [ -n "$_prune" ]; then printf '%s\n' "$_prune"; else printf '  none\n'; fi
    fi
    if [ "$present" -eq 0 ]; then
      printf 'no cache areas present\n'
      exit 2
    fi
    exit 0
    ;;
  gc|clear)
    if [ "${#SELECT[@]}" -eq 0 ] && [ "$ALL" != 1 ]; then
      usage
      exit 2
    fi
    for s in "${SELECT[@]}"; do
      _found=0
      for i in "${!A_NAME[@]}"; do
        if [ "$s" = "${A_NAME[$i]}" ]; then _found=1; break; fi
      done
      if [ "$_found" != 1 ]; then
        printf 'mise-cache: unknown area: %s\n' "$s" >&2
        usage
        exit 2
      fi
    done
    picked=()
    for i in "${!A_NAME[@]}"; do
      _take=0
      if [ "$ALL" = 1 ]; then
        if [ "${A_PRESENT[$i]}" = 1 ]; then
          if [ "$CMD" = gc ] && [ -n "${A_GC[$i]}" ]; then _take=1; fi
          if [ "$CMD" = clear ] && [ "${A_CLEAR[$i]}" != none ] && [ -n "${A_CLEAR[$i]}" ]; then _take=1; fi
        fi
      else
        for s in "${SELECT[@]}"; do
          if [ "$s" = "${A_NAME[$i]}" ]; then _take=1; break; fi
        done
      fi
      [ "$_take" = 1 ] || continue
      picked+=("$i")
    done
    if [ "${#picked[@]}" -eq 0 ]; then
      printf 'mise-cache: nothing selected has a %s action\n' "$CMD" >&2
      exit 2
    fi
    rc=0
    for i in "${picked[@]}"; do
      printf '%s:\n' "${A_NAME[$i]}"
      if [ "${A_PRESENT[$i]}" != 1 ]; then
        printf '  absent on this machine, skipping\n'
        continue
      fi
      if [ "$CMD" = gc ]; then
        if [ -z "${A_GC[$i]}" ]; then
          printf '  no gc action\n'
          continue
        fi
        run_native "${A_GC[$i]}" || rc=1
      else
        c="${A_CLEAR[$i]}"
        if [ -z "$c" ] || [ "$c" = none ]; then
          printf '  visibility only, no clear action\n'
          continue
        fi
        if [ "$c" = rm ]; then
          rm_paths "$i" || rc=1
        elif command -v "${c%% *}" >/dev/null 2>&1; then
          run_native "$c" || rc=1
        else
          printf '  %s not on PATH, removing paths directly\n' "${c%% *}"
          rm_paths "$i" || rc=1
        fi
      fi
    done
    exit "$rc"
    ;;
esac
{% endraw %}
