# status-proc.sh — generic cgroup-scoped /proc counter aggregation.
#
# Sibling of status-dirs.sh: that one DUMPS raw file contents of declared
# directories; this one COUNTS per-process /proc facts and aggregates them
# over systemd --user scopes. The kernel accounts none of these facts
# per-cgroup (cgroupfs carries no inotify/epoll/fd controllers — only
# pids/memory-style ones, which `systemctl show` already rolls up natively
# as MemoryCurrent/TasksCurrent), so scope rollup is this tool's /proc
# scan, not a kernel feature.
#
# Rollup semantics: a scope's counts include every process in its cgroup
# SUBTREE (component-wise prefix match), so parent scopes include children
# — app.slice counts opencode.service's fds plus every other member's.
# Declaring nested scopes double-counts; the defaults are disjoint.
#
# Scopes:
#   default       every active --user slice except the root -.slice: the
#                 user manager's top-level cgroups in systemd terms. Raw
#                 cgroupfs children are NOT used — they are ephemeral
#                 scope spam (tmux-spawn-*.scope et al.) that slice
#                 rollup absorbs anyway.
#   --scope NAME  any --user unit (service/slice/scope); inactive units
#                 report zero with an `inactive` note. `@user` = the whole
#                 uid, managed or not. `@slices` = the default set.
#   env           PROC_STATUS_SCOPES (colon-joined, rendered from the
#                 playbook's PROC_STATUS_SCOPES list by the status
#                 subsystem) is used when no --scope flags are given.
#
# Counters (one /proc pass computes all):
#   procs          processes in scope
#   fds            open fd entries (no kernel ceiling file; cf. LimitNOFILE)
#   inotify.watches        fdinfo "inotify wd:" lines summed over inotify fds
#                          (ceiling fs.inotify.max_user_watches — user-wide pool)
#   inotify.instances      inotify fds (ceiling fs.inotify.max_user_instances)
#   epoll/eventfd/timerfd/socket/memfd fds
#
# Drift: any scoped metric at >=90% of its ceiling (pools are user-wide;
# one scope exhausting them starves every other watcher on the user).
#
# Exit per status.sh convention: 0 clean, 1 drift, 2 usage error.
# Test seams: PROC_ROOT (default /proc), PROC_SYSTEMCTL (default
# `systemctl --user`).
#
# NOTE: this body is Jinja-rendered — no array-length idioms (the
# dollar-brace-hash sequence opens a Jinja comment); the scope count is
# tracked by hand.

_root="${PROC_ROOT:-/proc}"
_systemctl_cmd="${PROC_SYSTEMCTL:-systemctl --user}"
_systemctl() { $_systemctl_cmd "$@"; }
_topn=0
NSCOPES=0
HAVE_USER=0
WANT_SLICES=0
SCOPE_NAMES=()
SCOPE_CGS=()

_say() { printf '%-14s %s\n' "$1" "$2"; }

add_scope() { # $1 name, $2 cgroup ("" = inactive / @user)
  SCOPE_NAMES+=("$1")
  SCOPE_CGS+=("${2:-}")
  NSCOPES=$((NSCOPES + 1))
}

resolve_scope() { # $1 name -> cgroup on stdout ("" when unknown/inactive)
  case "$1" in
    @user|@slices) return 0 ;;
  esac
  _systemctl show "$1" -p ControlGroup --value 2>/dev/null | sed 's|^0::||'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)
      _s="${2:?--scope needs a name}"
      case "$_s" in
        @user)   HAVE_USER=1; add_scope "@user" "" ;;
        @slices) WANT_SLICES=1 ;;
        *)       add_scope "$_s" "$(resolve_scope "$_s")" ;;
      esac
      shift 2 ;;
    --top) _topn="${2:?--top needs a number}"; shift 2 ;;
    -h|--help)
      cat >&2 <<'EOF'
usage: status-proc.sh [--scope NAME]... [--top N]
  Aggregate per-process /proc counters over systemd --user cgroup scopes.
    --scope NAME  user unit (subtree rollup) | @user | @slices (repeatable)
    --top N       also list the N highest inotify-watch processes
  Default scopes: every active user slice (top-level cgroups), or the
  PROC_STATUS_SCOPES env list when no flags are given.
EOF
      exit 0 ;;
    *) printf 'status-proc.sh: unknown argument: %s (try --help)\n' "$1" >&2; exit 2 ;;
  esac
done

# scope set: flags > PROC_STATUS_SCOPES env > default slice enumeration
if [ "$NSCOPES" -eq 0 ] && [ "$HAVE_USER" -eq 0 ] && [ "$WANT_SLICES" -eq 0 ] && [ -n "${PROC_STATUS_SCOPES:-}" ]; then
  for _s in $(printf '%s' "$PROC_STATUS_SCOPES" | tr ':' ' '); do
    [ -n "$_s" ] || continue
    case "$_s" in
      @user)   HAVE_USER=1; add_scope "@user" "" ;;
      @slices) WANT_SLICES=1 ;;
      *)       add_scope "$_s" "$(resolve_scope "$_s")" ;;
    esac
  done
fi

if [ "$NSCOPES" -eq 0 ] && [ "$HAVE_USER" -eq 0 ] && [ "$WANT_SLICES" -eq 0 ]; then
  WANT_SLICES=1
fi

if [ "$WANT_SLICES" -eq 1 ]; then
  # read's word-splitting eats the leading indentation list-units emits
  while read -r _s _; do
    case "$_s" in
      -.slice|'') ;;
      *) add_scope "$_s" "$(resolve_scope "$_s")" ;;
    esac
  done < <(_systemctl list-units --type=slice --state=active --no-legend 2>/dev/null || true)
fi

if [ "$NSCOPES" -eq 0 ] && [ "$HAVE_USER" -eq 0 ]; then
  _say scopes "n/a: no active user slices and no scopes declared"
  exit 2
fi

_myuid="$(id -u)"
_maxw="$(cat "$_root/sys/fs/inotify/max_user_watches" 2>/dev/null || echo 0)"
_maxi="$(cat "$_root/sys/fs/inotify/max_user_instances" 2>/dev/null || echo 0)"

# one /proc pass; emit "scope|pid|comm|fds|ii|iw|ep|ev|tf|sk|md" per proc
_rows=""
for _p in "$_root"/[0-9]*; do
  _cg="$(sed -n 's/^0:://p' "$_p/cgroup" 2>/dev/null)"
  _uid=""
  _matched=""
  _i=0
  while [ "$_i" -lt "$NSCOPES" ]; do
    _s="${SCOPE_NAMES[$_i]}"
    if [ "$_s" = "@user" ]; then
      if [ -z "$_uid" ]; then _uid="$(awk '/^Uid:/{print $2; exit}' "$_p/status" 2>/dev/null || true)"; fi
      if [ "${_uid:-}" = "$_myuid" ]; then _matched="$_matched$_s|"; fi
    else
      _scg="${SCOPE_CGS[$_i]}"
      if [ -n "$_scg" ]; then
        case "$_cg" in
          "$_scg"|"$_scg"/*) _matched="$_matched$_s|" ;;
        esac
      fi
    fi
    _i=$((_i + 1))
  done
  [ -n "$_matched" ] || continue
  _fds=0; _ii=0; _iw=0; _ep=0; _ev=0; _tf=0; _sk=0; _md=0
  for _fd in "$_p"/fd/*; do
    _t="$(readlink "$_fd" 2>/dev/null)" || continue
    _fds=$((_fds + 1))
    case "$_t" in
      anon_inode:inotify*)
        _ii=$((_ii + 1))
        _n="$(grep -c '^inotify wd:' "$_p/fdinfo/${_fd##*/}" 2>/dev/null || true)"
        [ -n "$_n" ] || _n=0
        _iw=$((_iw + _n)) ;;
      anon_inode:*eventpoll*) _ep=$((_ep + 1)) ;;
      anon_inode:*eventfd*)   _ev=$((_ev + 1)) ;;
      anon_inode:*timerfd*)   _tf=$((_tf + 1)) ;;
      socket:*)               _sk=$((_sk + 1)) ;;
      memfd:*)                _md=$((_md + 1)) ;;
    esac
  done
  # herestring (not a pipe): _rows accumulation must stay in this shell
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    _rows="${_rows}${_s}|${_p##*/}|$(cat "$_p/comm" 2>/dev/null || echo '?')|$_fds|$_ii|$_iw|$_ep|$_ev|$_tf|$_sk|$_md
"
  done <<< "$(printf '%s' "$_matched" | tr '|' '\n')"
done

if [ -z "$_rows" ]; then
  _say scopes "OK: no processes matched any scope"
  exit 0
fi

_drift=0
_i=0
while [ "$_i" -lt "$NSCOPES" ]; do
  _s="${SCOPE_NAMES[$_i]}"
  _scg="${SCOPE_CGS[$_i]}"
  _i=$((_i + 1))
  if [ -z "$_scg" ] && [ "$_s" != "@user" ]; then
    _say "$_s" "inactive; no consumption"
    continue
  fi
  _agg="$(printf '%s' "$_rows" | awk -F'|' -v s="$_s" '$1==s {p++; f+=$4; ii+=$5; iw+=$6; ep+=$7; ev+=$8; tf+=$9; sk+=$10; md+=$11}
    END {printf "%d %d %d %d %d %d %d %d %d", p+0, f+0, ii+0, iw+0, ep+0, ev+0, tf+0, sk+0, md+0}' || true)"
  _procs="${_agg%% *}"
  _r="${_agg#* }"; _fds="${_r%% *}";  _r="${_r#* }"
  _ii="${_r%% *}";   _r="${_r#* }"
  _iw="${_r%% *}";   _r="${_r#* }"
  _ep="${_r%% *}";   _r="${_r#* }"
  _ev="${_r%% *}";   _r="${_r#* }"
  _tf="${_r%% *}";   _r="${_r#* }"
  _sk="${_r%% *}";   _md="${_r#* }"
  _wpct=$(( _iw * 100 / (_maxw > 0 ? _maxw : 1) ))
  _ipct=$(( _ii * 100 / (_maxi > 0 ? _maxi : 1) ))
  _line="procs $_procs | fds $_fds | inotify $_iw/$_maxw watches (${_wpct}%), $_ii/$_maxi inst (${_ipct}%)"
  _line="$_line | epoll $_ep | eventfd $_ev | timerfd $_tf | socket $_sk | memfd $_md"
  if [ "$_wpct" -ge 90 ] || [ "$_ipct" -ge 90 ]; then
    _say "$_s" "DRIFT: $_line — pool at >=90%, every watcher on the user starves"
    _drift=1
  else
    _say "$_s" "OK: $_line"
  fi
done

if [ "$_topn" -gt 0 ]; then
  { printf '%s' "$_rows" | sort -t'|' -k6 -rn | head -n "$_topn" || true; } | while IFS='|' read -r _s _pid _comm _fds _ii _iw _ep _ev _tf _sk _md; do
    _say top "${_iw} watches, ${_ii} inst, ${_fds} fds — pid ${_pid} (${_comm}) in ${_s}"
  done
fi

exit "$_drift"
