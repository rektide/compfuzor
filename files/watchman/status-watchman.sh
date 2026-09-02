# status-watchman.sh -- watchman daemon stats + health, via the watchman CLI.
#
# Hybrid deploy: paths are per-user (${HOME} literals, expanded at runtime);
# global artifacts live in /srv and /etc/opt. Everything here needs
# watchman-domain knowledge that no generic reporter covers:
#   - the daemon answers on the MANAGED socket and is the daemon our unit
#     started: `get-sockname` echoes the --sockname the unit passed, so an
#     ad-hoc daemon (spawned by a bare CLI without the guard config) shows
#     as a different sockname / a dead service with a live pidfile;
#   - the CLI-routing symlink is intact: bare `watchman` lands on the
#     managed daemon instead of auto-spawning an unguarded one;
#   - the resolved config is a parseable guard config; generic link status
#     separately reports whether the default config link is managed;
#   - the root guard is in effect: every watched root carries a root_files
#     marker (derived from the deployed config) and still exists on disk;
#   - the guard is not inverted: ~ and ~/archive stay marker-free (a .git/.jj
#     in ~ -- e.g. dotfiles -- would make every watch resolve to ~);
#   - guard refusals in the log window, informational: the daemon logs every
#     refused watch (send_error_response, with client pid + requested path);
#     the refused client only sees a JSON error -- and the CLI exits 0 on it
#     -- so background services retry silently. guard-refusals.sh aggregates;
#   - user linger is on, so the unit (and its guard config) runs from boot,
#     before any client could auto-spawn an unguarded daemon;
#   - the canonical service's inotify pressure vs fs.inotify.max_user_watches --
#     counting only processes in this unit's cgroup, not other user daemons;
#   - state/log artifact sizes (no rotation in this build; takeover.sh
#     trims at each start).
#
# All CLI probes use --no-spawn --no-local so a dead daemon is REPORTED,
# never resurrected as a side effect of checking.
#
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-applicable.
# Test seams: WATCHMAN_BIN, WATCHMAN_UNIT, WATCHMAN_ROOT_FILES (space-sep),
# WATCHMAN_STATUS_TIMEOUT (secs).

_vdir="${HOME}/.local/var/lib/watchman-main"
_sockdir="${XDG_STATE_HOME:-${HOME}/.local/state}/watchman/$(id -un)-state"
_uetc="${HOME}/.config/watchman-main"
_sock="$_sockdir/sock"
_pidfile="$_vdir/pid"
_statefile="$_vdir/state"
_logfile="$_vdir/log"
_cli_state="{{WATCHMAN_DEFAULT_STATE_DIR}}/$(id -un)-state"
_cfg="${WATCHMAN_CONFIG_FILE:-$_uetc/watchman.json}"
_wmbin="${WATCHMAN_BIN:-{{WATCHMAN_BIN}}}"
_unit="${WATCHMAN_UNIT:-{{SYSTEMD_SERVICE}}.service}"

_drift=0
_ipc_ok=0
_pid=""
_say() { printf '%-12s %s\n' "$1" "$2"; }
_hum() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }
_wm() { timeout "${WATCHMAN_STATUS_TIMEOUT:-5}" "$_wmbin" --no-spawn --no-local --sockname="$_sock" "$@"; }

command -v jq >/dev/null 2>&1 || { _say daemon "DRIFT: jq is required to parse watchman output"; exit 1; }

# --- guard config -----------------------------------------------------------
if [ -r "$_cfg" ] && _guard="$(jq -c '{enforce_root_files, root_files}' "$_cfg" 2>/dev/null)" && [ -n "$_guard" ]; then
  if [ "$(jq -r '.enforce_root_files == true' <<<"$_guard")" = true ]; then
    _say config "OK: $(jq -r '"enforce_root_files, markers " + (.root_files | join(" "))' <<<"$_guard")"
  else
    _say config "DRIFT: enforce_root_files is not true in $_cfg"; _drift=1
  fi
else
  _say config "DRIFT: $_cfg missing or unreadable"; _drift=1
fi

# Markers: the WATCHMAN_ROOT_FILES seam wins; else derive from the deployed
# config, mirroring the daemon (cfg_compute_root_files prepends
# .watchmanconfig, which is always honored even when not listed).
_markers="${WATCHMAN_ROOT_FILES:-}"
if [ -z "$_markers" ] && [ -r "$_cfg" ]; then
  _markers="$(jq -r '(.root_files // [".git", ".hg", ".jj", ".watch"]) + [".watchmanconfig"] | join(" ")' "$_cfg" 2>/dev/null || true)"
fi
: "${_markers:=.git .hg .jj .watch .watchmanconfig}"

# --- CLI routing symlink ----------------------------------------------------
if [ -L "$_cli_state" ] && [ "$(readlink -m "$_cli_state")" = "$(readlink -m "$_sockdir")" ]; then
  _say cli-route "OK: $_cli_state -> $_sockdir"
else
  _say cli-route "DRIFT: $_cli_state is not a symlink to $_sockdir -- bare CLI would spawn an unguarded daemon"
  _drift=1
fi

# --- systemd user service ---------------------------------------------------
_svc_state="n/a"
if command -v systemctl >/dev/null 2>&1; then
  _svc_state="$(systemctl --user is-active "$_unit" 2>/dev/null || true)"
  if [ "$_svc_state" = active ]; then
    _mainpid="$(systemctl --user show "$_unit" -p MainPID --value 2>/dev/null || echo 0)"
    _say service "OK: active ($_unit, MainPID ${_mainpid:-?})"
  else
    _say service "DRIFT: $_unit is '${_svc_state:-unknown}' -- daemon is not under systemd supervision"
    _drift=1
    _mainpid=0
  fi
else
  _say service "n/a: systemctl not available"
  _mainpid=0
fi

# --- daemon IPC -------------------------------------------------------------
if _ver_json="$(_wm version 2>&1)"; then
  _version="$(jq -r '.version // "unknown"' <<<"$_ver_json" 2>/dev/null)"
  _reported_sock="$(_wm get-sockname 2>/dev/null | jq -r '.sockname // empty' 2>/dev/null)"
  if [ "$_reported_sock" = "$_sock" ]; then
    _say daemon "OK: v$_version answering on managed socket"
  else
    _say daemon "DRIFT: v$_version answers but sockname is '${_reported_sock:-unreported}' -- not the managed daemon"
    _drift=1
  fi
  _ipc_ok=1
else
  _say daemon "DRIFT: no answer on $_sock within ${WATCHMAN_STATUS_TIMEOUT:-5}s (--no-spawn: not restarted)"
  _drift=1
fi

# --- pidfile ----------------------------------------------------------------
if [ -r "$_pidfile" ]; then
  _pid="$(tr -dc '0-9' <"$_pidfile")"
  if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null && [ "$(cat "/proc/$_pid/comm" 2>/dev/null || true)" = watchman ]; then
    if [ "${_mainpid:-0}" = "0" ]; then
      _say pid "OK: pidfile $_pid alive but not the unit's MainPID (ad-hoc daemon?)"
    elif [ "$_mainpid" = "$_pid" ]; then
      _say pid "OK: pidfile $_pid matches unit MainPID"
    else
      _say pid "DRIFT: pidfile says $_pid but unit MainPID is $_mainpid"
      _drift=1
    fi
    _uptime="$(ps -o etime= -p "$_pid" 2>/dev/null | tr -d ' ')"
    _say uptime "up ${_uptime:-?} (pid $_pid)"
  else
    _say pid "DRIFT: pidfile content '$_pid' is not a live watchman process"; _drift=1
    _pid=""
  fi
else
  _say pid "n/a: no pidfile at $_pidfile"
fi

# --- watched roots + guard enforcement --------------------------------------
if [ "$_ipc_ok" = 1 ]; then
  _roots_json="$(_wm watch-list 2>/dev/null || true)"
  if [ -n "$_roots_json" ] && _nroots="$(jq -r '.roots | length' <<<"$_roots_json" 2>/dev/null)"; then
    _gone=0; _nomark=0
    _offenders=""
    while IFS= read -r _root; do
      if [ ! -d "$_root" ]; then
        _gone=$((_gone + 1)); _offenders="$_offenders$_root|gone\n"; continue
      fi
      _marked=0
      for _m in $_markers; do
        if [ -e "$_root/$_m" ]; then _marked=1; break; fi
      done
      if [ "$_marked" = 0 ]; then
        _nomark=$((_nomark + 1)); _offenders="$_offenders$_root|no marker\n"
      fi
    done < <(jq -r '.roots[]' <<<"$_roots_json")
    if [ "$_gone" = 0 ] && [ "$_nomark" = 0 ]; then
      _say roots "OK: $_nroots watched, all on disk with VCS marker"
    else
      _say roots "DRIFT: $_nroots watched, $_gone gone, $_nomark without marker (guard bypassed; watch-del them)"
      _drift=1
      _shown=0
      while IFS='|' read -r _r _why; do
        [ "$_shown" -ge 5 ] && break
        printf '             %s (%s)\n' "$_r" "$_why"
        _shown=$((_shown + 1))
      done <<<"$(printf '%b' "$_offenders")"
    fi
  else
    _say roots "DRIFT: watch-list request failed"; _drift=1
  fi
fi

# --- inotify pressure of the canonical service -------------------------------
# Count every process in the unit cgroup. This excludes other watchman,
# watchwoman, editor, and OpenCode instances sharing the user's inotify pool.
if [ "${_svc_state:-}" = active ] && command -v systemctl >/dev/null 2>&1; then
  _service_cgroup="$(systemctl --user show "$_unit" -p ControlGroup --value 2>/dev/null || true)"
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
    _say inotify "DRIFT: service cgroup unavailable; cannot scope consumption"
    _drift=1
  fi
else
  _say inotify "n/a: canonical service inactive"
fi

# --- guard inversion: ~ and ~/archive must stay marker-free ------------------
# The root guard refuses bare ~/archive/~ only because no root_files marker
# exists along their path; a marker in ~ (dotfiles repo) or ~/archive would
# resolve every watch below it to that dir (watchman has no deny list).
_top_dirty=0
for _d in "$HOME" "$HOME/archive"; do
  [ -d "$_d" ] || continue
  for _m in $_markers; do
    if [ -e "$_d/$_m" ]; then
      _say guard-top "DRIFT: $_d/$_m exists -- guard would resolve bare $_d to a repo"
      _top_dirty=1
    fi
  done
done
if [ "$_top_dirty" = 0 ]; then
  _say guard-top "OK: ~ and ~/archive marker-free (bare watch of them refused)"
else
  _drift=1
fi

# --- linger -------------------------------------------------------------------
# Without linger the unit (and its guard config) only starts at first login;
# until then a bare CLI auto-spawns an unguarded daemon. Operational choice:
# enable via `loginctl enable-linger $USER` (needs polkit/root; not settable
# from this user-mode playbook).
if command -v loginctl >/dev/null 2>&1; then
  if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" = yes ]; then
    _say linger "OK: user lingering (unit runs from boot)"
  else
    _say linger "DRIFT: linger off -- unit starts only after first login"
    _drift=1
  fi
fi

# --- artifacts + log health --------------------------------------------------
# This build has no max_log rotation; takeover.sh trims at each start, so
# only sustained growth between restarts can pass the 256MiB drift threshold.
_art="state $(_hum "$(stat -c %s "$_statefile" 2>/dev/null || echo 0)")"
if [ -f "$_logfile" ]; then
  _logsize="$(stat -c %s "$_logfile")"
  _art="$_art, log $(_hum "$_logsize")"
  if [ "$_logsize" -gt 268435456 ]; then
    _say artifacts "DRIFT: $_art -- exceeds 256MiB (no rotation; truncate + restart)"
    _drift=1
  else
    _say artifacts "OK: $_art"
  fi
  _poison="$(tail -n 20000 "$_logfile" 2>/dev/null | grep -Eaic 'poison|ENOSPC' || true)"
  if [ "$_poison" -gt 0 ]; then
    _say log-health "DRIFT: $_poison poison/ENOSPC line(s) in last 20000 log lines"
    _drift=1
  else
    _say log-health "OK: no poison/ENOSPC lines in last 20000 log lines"
  fi
  # --- guard refusals (informational, not drift) -----------------------------
  # Both refusal paths log the same signature text: watch-project walks UP
  # for a marker ("resolve_projpath: None of the files listed..."); plain
  # watch checks the dir itself ("Your watchman administrator... None of
  # the files listed..."). Window = since the last takeover.sh trim/restart.
  _refus="$(grep -ac 'None of the files listed in global config root_files' "$_logfile" 2>/dev/null || true)"
  if [ "${_refus:-0}" -gt 0 ]; then
    _top="$(grep -a 'None of the files listed in global config root_files' "$_logfile" \
      | sed -E 's/.*send_error_response: (\[[^]]*\]).*/\1/' | sort | uniq -c | sort -rn | head -1)"
    _say guard-hits "info: ${_refus} refusal(s) in log window; top: $(printf '%s' "$_top" | sed -E 's/^ *([0-9]+) /\1x /') (see guard-refusals.sh)"
  else
    _say guard-hits "OK: no guard refusals in log window"
  fi
else
  _say artifacts "OK: $_art (no log yet)"
fi

exit "$_drift"
