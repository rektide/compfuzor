# status-watchwoman.sh -- socket-activated watchwoman daemon health + drift.
#
# Hybrid deploy, zeroconf routing: the socket unit binds the XDG state-home
# path the CLI resolves with no environment ($XDG_STATE_HOME unset →
# ~/.local/state/watchman/<user>-state/sock), so client routing has no env
# vars or symlink farm to drift. What's left is all watchwoman-specific:
#
#   - the deployed binary IS the managed build ({{REPO_DIR}}/target/release/watchwoman);
#   - both units are compfuzor-managed symlinks (generic link status also
#     reports these, but here with unit semantics: the SOCKET is the
#     enabled one, the service must stay link-only);
#   - the socket unit is enabled + active: with linger on, the socket is
#     bound from boot, which is what keeps bare CLIs from ever auto-
#     spawning a rival daemon (the C++ watchman takeover problem is
#     structural here, not procedural);
#   - ListenStream agrees with the zeroconf path the CLI resolves
#     (get-sockname) — the XDG_STATE_HOME-drift tripwire;
#   - the running daemon (if any) is the unit's: get-pid == MainPID;
#   - no rival daemon: a socket file while the units are inactive, or a
#     foreground-daemon process outside the unit, is a CLI-spawned
#     squatter holding the name systemd should own;
#   - the classic-watchman compat symlink (upstream's default socket
#     location) points at the zeroconf socket;
#   - roots health via `status --json`: dead/missing roots as drift,
#     plus marker-less roots informational (watchwoman has NO
#     enforce_root_files guard — watch-project falls back to the path
#     itself, so a bare `watch-project ~` is a real hazard the old
#     guard refused);
#   - inotify instances held by the daemon (informational — the
#     exhaustion vector the C++ deploy's FD guard existed for).
#
# Daemon probes are gated on the service being active: an idle
# socket-activated daemon is NORMAL, and probing would START it — this
# reporter never triggers activation.
#
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-applicable.
# Test seams: WATCHWOMAN_BIN, WATCHWOMAN_SOCKET_UNIT, WATCHWOMAN_SERVICE_UNIT,
# WATCHWOMAN_STATUS_TIMEOUT (secs).

_wmbin="${WATCHWOMAN_BIN:-watchwoman}"
_sock_unit="${WATCHWOMAN_SOCKET_UNIT:-watchwoman.socket}"
_svc_unit="${WATCHWOMAN_SERVICE_UNIT:-watchwoman.service}"

_expected_sock="${HOME}/.local/state/watchman/$(id -un)-state/sock"
_dir="{{DIR}}"
_target_bin="{{REPO_DIR}}/target/release/watchwoman"
_managed_etc="{{ETC}}"
_timeout="${WATCHWOMAN_STATUS_TIMEOUT:-5}"

_drift=0
_say() { printf '%-14s %s\n' "$1" "$2"; }
_hum() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }
_sys() { timeout "$_timeout" systemctl --user "$@"; }
_daemon() { timeout "$_timeout" "$_wmbin" --no-spawn "$@"; }

command -v jq >/dev/null 2>&1 || { _say daemon "DRIFT: jq is required to parse watchwoman output"; exit 1; }

# --- binary identity ---------------------------------------------------------
_bin_res="$(command -v "$_wmbin" 2>/dev/null || true)"
if [ -z "$_bin_res" ]; then
  _say binary "DRIFT: $_wmbin not on PATH (run {{BINS_DIR}}/install.sh)"
  exit 1
fi
_bin_real="$(readlink -f "$_bin_res" 2>/dev/null || true)"
_target_real="$(readlink -f "$_target_bin" 2>/dev/null || true)"
if [ -z "$_target_real" ]; then
  _say binary "DRIFT: managed build missing ($_target_bin); run the playbook"
  exit 1
elif [ "$_bin_real" != "$_target_real" ]; then
  _drift=1
  _say binary "DRIFT: $_bin_res -> ${_bin_real:-?} is not the managed build ($_target_bin)"
else
  _say binary "OK: $_bin_res -> ${_bin_real#${_dir}/}"
fi
# A cargo-installed copy in ~/.cargo/bin shadows the managed binary (the
# rust user-leaf of a bare install-user.sh run does this).
case "$_bin_real" in
  "${HOME}"/.cargo/bin/*)
    _drift=1
    _say binary "DRIFT: $_bin_res resolves into ~/.cargo/bin — a cargo install shadows the managed build; remove it"
    ;;
esac

# --- `watchman` name: this deploy owns it --------------------------------------
# The argv[0] alias must resolve to this build (RUST_ALL links it; a
# foreign resolution means the C++ deploy is still installed or something
# else squats the name).
if command -v watchman >/dev/null 2>&1; then
  _wm_res="$(command -v watchman)"
  _wm_real="$(readlink -f "$_wm_res" 2>/dev/null || true)"
  if [ "$_wm_real" = "$_target_real" ]; then
    _say binary "OK: $_wm_res -> this build (drop-in name owned)"
  else
    _drift=1
    _say binary "DRIFT: $_wm_res -> ${_wm_real:-?} is not this build ($_target_bin) — retire the foreign watchman and run {{BINS_DIR}}/install.sh"
  fi
else
  _drift=1
  _say binary "DRIFT: no watchman on PATH — run {{BINS_DIR}}/install.sh (RUST_ALL links the alias)"
fi

# --- units: managed symlinks, enablement, activity ---------------------------
for _u in "$_sock_unit" "$_svc_unit"; do
  _link="${HOME}/.config/systemd/user/$_u"
  if [ ! -e "$_link" ]; then
    _drift=1
    _say "unit:$_u" "DRIFT: not installed (run {{BINS_DIR}}/activate-user.sh)"
    continue
  fi
  _real="$(readlink -f "$_link" 2>/dev/null || true)"
  _want="$(readlink -f "$_managed_etc/$_u" 2>/dev/null || true)"
  if [ -z "$_want" ] || [ "$_real" != "$_want" ]; then
    _drift=1
    _say "unit:$_u" "DRIFT: $_link -> ${_real:-?} is not the managed unit ($_want)"
  else
    _say "unit:$_u" "OK: managed -> ${_real#${_dir}/}"
  fi
done

# The socket is the enabled unit; the service stays link-only by design.
case "$(_sys is-enabled "$_sock_unit" 2>/dev/null)" in
  enabled) _say enablement "OK: $_sock_unit enabled (activates $_svc_unit on first connect)";;
  *) _drift=1; _say enablement "DRIFT: $_sock_unit not enabled — run {{BINS_DIR}}/activate-user.sh";;
esac
case "$(_sys is-enabled "$_svc_unit" 2>/dev/null)" in
  enabled) _drift=1; _say "unit:$_svc_unit" "DRIFT: service must stay link-only (socket-activated; enabling it fights the design)";;
esac

case "$(_sys is-active "$_sock_unit" 2>/dev/null)" in
  active) _say socket "OK: $_sock_unit active (bound from boot via linger)";;
  *) _drift=1; _say socket "DRIFT: $_sock_unit inactive — bare CLIs will auto-spawn unmanaged daemons";;
esac

if [ "$(loginctl show-user "$(id -un)" -p Linger 2>/dev/null)" = "Linger=yes" ]; then
  _say linger "OK: on (user manager + socket from boot)"
else
  _drift=1; _say linger "DRIFT: off — loginctl enable-linger $(id -un)"
fi

# --- ListenStream vs zeroconf contract ----------------------------------------
if _sys show "$_sock_unit" -p Listen 2>/dev/null | grep -q "$_expected_sock"; then
  _say listen "OK: ListenStream is the zeroconf path ($_expected_sock)"
else
  _drift=1
  _say listen "DRIFT: $_sock_unit ListenStream does not name $_expected_sock (get-sockname and systemd disagree)"
fi

# --- daemon identity / rivals --------------------------------------------------
_svc_state="$(_sys is-active "$_svc_unit" 2>/dev/null || true)"
_main_pid="$(_sys show "$_svc_unit" -p MainPID --value 2>/dev/null || true)"
if [ "$_svc_state" = active ] && [ "${_main_pid:-0}" -gt 0 ] 2>/dev/null; then
  _dpid="$(_daemon get-pid 2>/dev/null | jq -r '.pid // empty')"
  if [ -n "$_dpid" ] && [ "$_dpid" = "$_main_pid" ]; then
    _say daemon "OK: pid $_main_pid is the unit's (get-pid agrees)"
  else
    _drift=1
    _say daemon "DRIFT: unit MainPID=${_main_pid:-?} but daemon reports '${_dpid:-none}' (rival on the socket?)"
  fi
else
  _say daemon "idle: socket-activated, not started yet (normal)"
fi

# Rival scan — listener custody on the path, not mere file presence (with
# socket activation the file exists whenever the SOCKET unit is bound,
# regardless of the service). The healthy states: systemd holds the
# listener (socket unit live; daemon optional). Drift: a watchwoman
# process holds it while the service is inactive (CLI auto-spawned
# orphan past a deaf/stopped socket unit), or the file exists with no
# listener at all (stale).
_sock_state="$(_sys is-active "$_sock_unit" 2>/dev/null || true)"
_listener_line="$(ss -H -xlp 2>/dev/null | grep -F "$_expected_sock" | head -1 || true)"
if [ -n "$_listener_line" ]; then
  case "$_listener_line" in
    *'users:(("watchwoman"'*)
      if [ "$_svc_state" != active ]; then
        _drift=1
        _say rival "DRIFT: a watchwoman process outside the unit listens on $_expected_sock (CLI-spawned orphan; shutdown-server it, then restart $_sock_unit)"
      fi
      ;;
    *'users:(("systemd"'*)
      if [ "$_sock_state" != active ]; then
        _drift=1
        _say rival "DRIFT: systemd listens on $_expected_sock but $_sock_unit is $_sock_state"
      fi
      ;;
  esac
elif [ -S "$_expected_sock" ]; then
  _drift=1
  _say rival "DRIFT: $_expected_sock exists with no listener (stale file, or $_sock_unit deafened by a daemon-reload — restart it)"
fi
_strays="$(pgrep -f '[w]atchwoman.*--foreground-daemon' 2>/dev/null | grep -vx "${_main_pid:-none}" || true)"
if [ -n "$_strays" ]; then
  _drift=1
  _say rival "DRIFT: foreground daemons outside the unit: $(echo $_strays | tr '\n' ' ')"
fi

# --- roots health (only when the daemon is up; probing would start it) ---------
if [ "$_svc_state" = active ]; then
  _st="$(timeout "$_timeout" "$_wmbin" --no-spawn status --json 2>/dev/null || true)"
  if [ -n "$_st" ]; then
    # health classes: active | idle (normal, no subs yet) | stale (GC will
    # reap) | missing/dead (directory gone — real drift).
    _roots_n="$(jq -r '.roots | length' <<<"$_st" 2>/dev/null || echo '?')"
    _bad="$(jq -r '[.roots[] | select(.health == "dead" or .health == "missing")] | length' <<<"$_st" 2>/dev/null || echo '?')"
    _stale="$(jq -r '[.roots[] | select(.health == "stale")] | length' <<<"$_st" 2>/dev/null || echo '?')"
    _rss="$(jq -r '.rss_bytes // "?"' <<<"$_st" 2>/dev/null || echo '?')"
    _up="$(jq -r '.uptime_seconds // "?"' <<<"$_st" 2>/dev/null || echo '?')"
    _say roots "${_roots_n} watched; rss $(_hum "${_rss:-0}"); uptime ${_up}s; stale ${_stale}; dead/missing ${_bad}"
    if [ "$_bad" != 0 ]; then
      _drift=1
      jq -r '.roots[] | select(.health == "dead" or .health == "missing") | "  \(.health) \(.path) (missing_ticks \(.missing_ticks))"' <<<"$_st" 2>/dev/null
    fi
    # No enforce_root_files in watchwoman: surface marker-less roots so a
    # runaway `watch-project ~` is at least visible. Markers mirror the
    # daemon's own ROOT_MARKERS set.
    jq -r '.roots[].path' <<<"$_st" 2>/dev/null | while read -r _p; do
      for _m in .git .hg .svn .jj .watchmanconfig package.json Cargo.toml mix.exs pyproject.toml go.mod; do
        if [ -e "$_p/$_m" ]; then continue 2; fi
      done
      _say root-guard "info: marker-less root watched (no guard in watchwoman): $_p"
    done
  else
    _drift=1
    _say roots "DRIFT: daemon active but status --json failed"
  fi

  # inotify pressure (informational): instance count vs the system cap.
  if [ "${_main_pid:-0}" -gt 0 ] 2>/dev/null && [ -d "/proc/$_main_pid/fd" ]; then
    _inst="$(ls -l /proc/$_main_pid/fd 2>/dev/null | grep -c inotify || true)"
    _cap="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo '?')"
    _say inotify "info: ${_inst} inotify instances (cap ${_cap}) held by pid $_main_pid"
  fi
fi

# --- classic-watchman compat symlink -------------------------------------------
_compat_sock="{{WATCHWOMAN_COMPAT_ROOT}}/$(id -un)-state/sock"
if [ -L "$_compat_sock" ]; then
  if [ "$(readlink "$_compat_sock")" = "$_expected_sock" ]; then
    _say compat "OK: $_compat_sock -> zeroconf socket"
  else
    _drift=1
    _say compat "DRIFT: $_compat_sock -> $(readlink "$_compat_sock") (expected $_expected_sock)"
  fi
else
  _drift=1
  _say compat "DRIFT: no compat symlink at $_compat_sock ({{BINS_DIR}}/activate-user.sh lays it)"
fi

if [ "$_drift" != 0 ]; then
  _say result "DRIFT"
  exit 1
fi
_say result "OK"
exit 0
