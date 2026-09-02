# status-watchwoman.sh -- socket-activated watchwoman daemon drift report.
#
# The design's promises, each mapped to one check: the managed build owns
# both names; the units are compfuzor-managed and the socket is enabled +
# active (linger on = bound from boot); ListenStream is the default path
# the CLI resolves; the running daemon is the unit's; roots are healthy;
# the compat LINK is laid.
#
# Daemon probes are gated on the service being active — probing a
# socket-activated daemon would START it; this reporter never triggers
# activation.
#
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-applicable.
# Test seams: WATCHWOMAN_BIN, WATCHWOMAN_SOCKET_UNIT, WATCHWOMAN_SERVICE_UNIT,
# WATCHWOMAN_STATUS_TIMEOUT (secs).

_wmbin="${WATCHWOMAN_BIN:-{{GLOBAL_BINS_DIR}}/watchwoman}"
_sock_unit="${WATCHWOMAN_SOCKET_UNIT:-watchwoman.socket}"
_svc_unit="${WATCHWOMAN_SERVICE_UNIT:-watchwoman.service}"
_expected_sock="${XDG_STATE_HOME:-${HOME}/.local/state}/watchman/$(id -un)-state/sock"
_target_real="$(readlink -f "{{REPO_DIR}}/target/release/watchwoman" 2>/dev/null || true)"
_managed_etc="{{ETC}}"
_timeout="${WATCHWOMAN_STATUS_TIMEOUT:-5}"

_drift=0
_say() { printf '%-14s %s\n' "$1" "$2"; }
_hum() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }
_sys() { timeout "$_timeout" systemctl --user "$@"; }
_daemon() { timeout "$_timeout" "$_wmbin" --no-spawn "$@"; }

command -v jq >/dev/null 2>&1 || { _say daemon "DRIFT: jq is required to parse watchwoman output"; exit 1; }

# --- binaries: this deploy owns both names ------------------------------------
if [ -z "$_target_real" ]; then
  _say binary "DRIFT: managed build missing ({{REPO_DIR}}/target/release/watchwoman); run the playbook"
  exit 1
fi
for _name in "$_wmbin" watchman; do
  _res="$(command -v "$_name" 2>/dev/null || true)"
  if [ -z "$_res" ]; then
    _drift=1
    _say binary "DRIFT: $_name not on PATH (run {{BINS_DIR}}/install.sh)"
  elif [ "$(readlink -f "$_res" 2>/dev/null || true)" != "$_target_real" ]; then
    _drift=1
    _say binary "DRIFT: $_res is not the managed build ($_target_real)"
  else
    _say binary "OK: $_res -> managed build"
  fi
done

# --- units: managed symlinks, socket enabled + active -------------------------
for _u in "$_sock_unit" "$_svc_unit"; do
  _link="${HOME}/.config/systemd/user/$_u"
  if [ ! -e "$_link" ]; then
    _drift=1
    _say "unit:$_u" "DRIFT: not installed (run {{BINS_DIR}}/install-user.sh)"
  elif [ "$(readlink -f "$_link" 2>/dev/null || true)" != "$(readlink -f "$_managed_etc/$_u" 2>/dev/null || true)" ]; then
    _drift=1
    _say "unit:$_u" "DRIFT: $_link is not the managed unit"
  else
    _say "unit:$_u" "OK: managed"
  fi
done
case "$(_sys is-enabled "$_sock_unit" 2>/dev/null || true)" in
  enabled) _say enablement "OK: $_sock_unit enabled (activates $_svc_unit)";;
  *) _drift=1; _say enablement "DRIFT: $_sock_unit not enabled";;
esac
case "$(_sys is-active "$_sock_unit" 2>/dev/null || true)" in
  active) _say socket "OK: $_sock_unit active";;
  *) _drift=1; _say socket "DRIFT: $_sock_unit inactive";;
esac
if [ "$(loginctl show-user "$(id -un)" -p Linger 2>/dev/null)" = "Linger=yes" ]; then
  _say linger "OK: on (user manager + socket from boot)"
else
  _drift=1; _say linger "DRIFT: off — loginctl enable-linger $(id -un)"
fi
if _sys show "$_sock_unit" -p Listen 2>/dev/null | grep -q "$_expected_sock"; then
  _say listen "OK: ListenStream is the CLI's default path ($_expected_sock)"
else
  _drift=1
  _say listen "DRIFT: $_sock_unit ListenStream does not name $_expected_sock (get-sockname and systemd disagree — is XDG_STATE_HOME set?)"
fi

# --- daemon (only when up; probing would start it) -----------------------------
_svc_state="$(_sys is-active "$_svc_unit" 2>/dev/null || true)"
_main_pid="$(_sys show "$_svc_unit" -p MainPID --value 2>/dev/null || true)"
if [ "$_svc_state" = active ] && [ "${_main_pid:-0}" -gt 0 ] 2>/dev/null; then
  _dpid="$(_daemon get-pid 2>/dev/null | jq -r '.pid // empty')"
  if [ -n "$_dpid" ] && [ "$_dpid" = "$_main_pid" ]; then
    _say daemon "OK: pid $_main_pid is the unit's (get-pid agrees)"
  else
    _drift=1
    _say daemon "DRIFT: unit MainPID=${_main_pid:-?} but daemon reports '${_dpid:-none}'"
  fi
  _st="$(timeout "$_timeout" "$_wmbin" --no-spawn status --json 2>/dev/null || true)"
  if [ -n "$_st" ]; then
    _roots_n="$(jq -r '.roots | length' <<<"$_st" 2>/dev/null || echo '?')"
    _bad="$(jq -r '[.roots[] | select(.health == "dead" or .health == "missing")] | length' <<<"$_st" 2>/dev/null || echo '?')"
    _rss="$(jq -r '.rss_bytes // "?"' <<<"$_st" 2>/dev/null || echo '?')"
    _say roots "${_roots_n} watched; rss $(_hum "${_rss:-0}"); dead/missing ${_bad}"
    [ "$_bad" = 0 ] || { _drift=1; jq -r '.roots[] | select(.health == "dead" or .health == "missing") | "  \(.health) \(.path)"' <<<"$_st" 2>/dev/null; }
  else
    _drift=1
    _say roots "DRIFT: daemon active but status --json failed"
  fi

  # Count only processes in the canonical service cgroup. The user's other
  # OpenCode/editor instances are intentionally excluded from this report.
  _service_cgroup="$(_sys show "$_svc_unit" -p ControlGroup --value 2>/dev/null || true)"
  _service_watches=0
  _service_instances=0
  _service_processes=0
  if [ -n "$_service_cgroup" ]; then
    for _proc in /proc/[0-9]*; do
      _proc_cgroup="$(sed -n 's/^0:://p' "$_proc/cgroup" 2>/dev/null || true)"
      case "$_proc_cgroup" in
        "$_service_cgroup"|"$_service_cgroup"/*) ;;
        *) continue ;;
      esac
      _proc_instances=0
      _proc_watches=0
      for _fd in "$_proc"/fd/*; do
        [ "$(readlink "$_fd" 2>/dev/null || true)" = anon_inode:inotify ] || continue
        _proc_instances=$((_proc_instances + 1))
        _fd_watches="$(awk '/^inotify wd:/{c++} END{print c+0}' "$_proc/fdinfo/${_fd##*/}" 2>/dev/null || echo 0)"
        _proc_watches=$((_proc_watches + _fd_watches))
      done
      [ "$_proc_instances" -gt 0 ] || continue
      _service_processes=$((_service_processes + 1))
      _service_instances=$((_service_instances + _proc_instances))
      _service_watches=$((_service_watches + _proc_watches))
    done
    _max="$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
    _pct=$(( _service_watches * 100 / (_max > 0 ? _max : 1) ))
    if [ "$_pct" -ge 90 ]; then
      _say inotify "DRIFT: $_service_watches/$_max watches (${_pct}%), $_service_instances instances, $_service_processes process(es) -- service only"
      _drift=1
    else
      _say inotify "OK: $_service_watches/$_max watches (${_pct}%), $_service_instances instances, $_service_processes process(es) -- service only"
    fi
  else
    _drift=1
    _say inotify "DRIFT: service cgroup unavailable; cannot scope consumption"
  fi
else
  _say daemon "idle: socket-activated, not started yet (normal)"
  _say inotify "n/a: canonical service inactive"
fi

# --- compat link (links.ts owns it) --------------------------------------------
_compat_sock="{{WATCHMAN_DEFAULT_PREFIX}}/$(id -un)-state/sock"
if [ -L "$_compat_sock" ] && [ "$(readlink "$_compat_sock")" = "$_expected_sock" ]; then
  _say compat "OK: $_compat_sock -> default socket"
else
  _drift=1
  _say compat "DRIFT: no compat symlink at $_compat_sock ({{BINS_DIR}}/install-user.sh lays it via links.ts)"
fi

if [ "$_drift" != 0 ]; then
  _say result "DRIFT"
  exit 1
fi
_say result "OK"
exit 0
