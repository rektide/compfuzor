# status-atuin.sh -- atuin daemon health + hybrid-deploy drift reporter.
#
# HYBRID DEPLOY (watchman.srv.pb model): global artifacts -- repo at {{DIR}},
# unit templates at {{ETC}} (symlinked from DIR/etc), daemon fragment at
# {{ETC}}/daemon.conf. Per-user activation ({{DIR}}/bin/install-user.sh, no
# sudo) links the units into ~/.config/systemd/user and injects the managed
# [daemon] block into ~/.config/atuin/config.toml. Per-user state is
# inherently XDG (nothing to redirect -- unlike watchman there is no
# compile-time socket path baked into the binary):
#   socket   $XDG_RUNTIME_DIR/atuin.sock    (the .socket unit's ListenStream)
#   pidfile  ~/.local/share/atuin/atuin-daemon.pid
#   history  ~/.local/share/atuin/*.db
#
# ROUTING: unlike watchman there is no client env var (no ATUIN_SOCKET) --
# the [daemon] block in config.toml IS the client->daemon routing, so this
# reporter pins config/unit/socket AGREEMENT instead of a routing symlink.
#
# Checks:
#   - the user units are managed links to {{ETC}} (not hand-edited copies);
#   - enablement: socket ON, service deliberately OFF (an enabled service
#     would start without the socket-activation fd and fail with
#     "missing systemd socket" -- socket activation only);
#   - ListenStream (with %t expanded) == config daemon.socket_path == the
#     socket file the hooks connect to;
#   - managed-block integrity: the three keys enabled/autostart/systemd_socket
#     are present, uncommented, inside the atuin-daemon markers -- this
#     catches a manual comment-out/disable of the managed block;
#   - no duplicate [daemon] keys OUTSIDE the managed block (TOML duplicate
#     keys make atuin's parser fail outright);
#   - daemon identity: service MainPID vs pidfile pid (alive, comm=atuin) vs
#     daemon-reported status;
#   - version agreement: pidfile records the daemon's atuin version; a
#     mismatch with the CLI means the deployed binary moved on -- restart;
#   - foreign socket: socket file exists while our socket unit is inactive --
#     atuin cannot CLI-autostart a rival daemon under systemd_socket = true
#     (autostart is refused as incompatible), so this is a stale socket left
#     by an unclean shutdown; the socket unit cannot bind through it;
#   - informational only: linger (sync continuity before first login) and
#     search_mode daemon-fuzzy (interactive search pointed at the daemon;
#     managed top-level key via the playbook's ATUIN_SEARCH_MODE).
#
# An idle daemon is VALID: the socket unit activates the service on the
# first history hook, so an inactive service under an active socket is OK,
# not drift. Probes that would themselves trigger activation (`atuin daemon
# status` connects through the socket) run only when the service is already
# active -- status must observe, never start.
#
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-activated.
# Test seams: ATUIN_BIN, ATUIN_UNIT_BASE, ATUIN_CFG, ATUIN_RUNTIME_DIR,
# ATUIN_DATA_DIR, ATUIN_USER_UNITS. COMPFUZOR_EMERGENCY makes an intentionally
# stopped socket healthy for the invoking shell.

_atbin="${ATUIN_BIN:-{{GLOBAL_BINS_DIR}}/atuin}"
_ubase="${ATUIN_UNIT_BASE:-atuin-daemon}"
_rundir="${ATUIN_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-$HOME/.local/share/atuin}}"
_datadir="${ATUIN_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/atuin}"
_cfg="${ATUIN_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml}"
_uunits="${ATUIN_USER_UNITS:-$HOME/.config/systemd/user}"
_emergency="${COMPFUZOR_EMERGENCY:-0}"

_drift=0
_say() { printf '%-12s %s\n' "$1" "$2"; }

# --- activation ---------------------------------------------------------------
# Never activated for this user: units absent AND no managed block -> n/a.
if ! systemctl --user cat "${_ubase}.socket" >/dev/null 2>&1 \
   && { [ ! -f "$_cfg" ] || ! grep -q '^# atuin-daemon start' "$_cfg" 2>/dev/null; }; then
  _say activate "n/a: not activated for this user -- run {{DIR}}/bin/install-user.sh"
  exit 2
fi

# --- managed unit links ---------------------------------------------------------
for _t in socket service; do
  _u="$_uunits/${_ubase}.$_t"
  _src="{{ETC}}/${_ubase}.$_t"
  if [ -L "$_u" ] && [ "$(readlink -m "$_u" 2>/dev/null)" = "$(readlink -m "$_src" 2>/dev/null)" ]; then
    _say "unit-$_t" "OK: ${_u#/home/\$USER/} -> ${_src}"
  elif [ -e "$_u" ]; then
    _say "unit-$_t" "DRIFT: $_u exists but is not the managed link to $_src (re-run install-user.sh)"
    _drift=1
  else
    _say "unit-$_t" "DRIFT: $_u missing (re-run install-user.sh)"
    _drift=1
  fi
done

# --- enablement -----------------------------------------------------------------
_en_sock="$(systemctl --user is-enabled "${_ubase}.socket" 2>/dev/null || true)"
if [ "$_en_sock" = enabled ]; then
  _say enable "OK: ${_ubase}.socket enabled (activates the service on the first history hook)"
else
  _say enable "DRIFT: ${_ubase}.socket is '${_en_sock:-unknown}' (re-run {{DIR}}/bin/install-user.sh)"
  _drift=1
fi
_en_svc="$(systemctl --user is-enabled "${_ubase}.service" 2>/dev/null || true)"
if [ "$_en_svc" = enabled ]; then
  _say enable-svc "DRIFT: ${_ubase}.service is enabled -- it would start without the socket-activation fd and fail ('missing systemd socket'); socket activation only"
  _drift=1
else
  _say enable-svc "OK: ${_ubase}.service not enabled (socket-activated by design)"
fi

# --- socket unit active + path agreement -----------------------------------------
_sock_state="$(systemctl --user is-active "${_ubase}.socket" 2>/dev/null || true)"
if [ "$_sock_state" = active ]; then
  _say socket "OK: ${_ubase}.socket active (listening)"
elif [ "$_emergency" = 1 ]; then
  _say socket "OK: ${_ubase}.socket intentionally stopped by emergency mode"
else
  _say socket "DRIFT: ${_ubase}.socket is '${_sock_state:-unknown}' (enabled sockets start at login; or: systemctl --user start ${_ubase}.socket)"
  _drift=1
fi

# ListenStream from the unit (%t = runtime dir) vs config daemon.socket_path
# (unset means atuin's default: <runtime dir>/atuin.sock).
_ls="$(systemctl --user cat "${_ubase}.socket" 2>/dev/null | sed -n 's/^ListenStream=//p' | head -1)"
_ls_exp="${_ls/\%t/$_rundir}"
_cfg_socket="$(awk '
  /^[[:space:]]*\[daemon\]/ { ind = 1; next }
  /^[[:space:]]*\[/ { ind = 0 }
  ind && $0 ~ /^[[:space:]]*socket_path[[:space:]]*=/ {
    sub(/^[[:space:]]*socket_path[[:space:]]*=[[:space:]]*/, "")
    gsub(/"/, ""); print; exit
  }' "$_cfg" 2>/dev/null)"
_exp_sock="$_rundir/atuin.sock"
[ -n "$_cfg_socket" ] && _exp_sock="$_cfg_socket"
if [ -n "$_ls_exp" ] && [ "$_ls_exp" = "$_exp_sock" ]; then
  _say sock-path "OK: unit ListenStream (${_ls:-?} -> $_ls_exp) == config socket_path $_exp_sock"
else
  _say sock-path "DRIFT: unit ListenStream '${_ls_exp:-none}' != config socket_path '$_exp_sock' -- hooks would miss the daemon"
  _drift=1
fi

# --- managed config block integrity ----------------------------------------------
# The [daemon] block injected by install-atuin-config.sh must carry its three
# keys UNcommented inside the markers; the common drift is a manual
# comment-out (disable) of the whole block.
if grep -q '^# atuin-daemon start' "$_cfg" 2>/dev/null && grep -q '^# atuin-daemon end' "$_cfg" 2>/dev/null; then
  _block="$(sed -n '/^# atuin-daemon start/,/^# atuin-daemon end/p' "$_cfg")"
  for _kv in 'enabled:true' 'autostart:false' 'systemd_socket:true'; do
    _k="${_kv%%:*}"
    _v="${_kv##*:}"
    if printf '%s\n' "$_block" | grep -Eq "^[[:space:]]*${_k}[[:space:]]*=[[:space:]]*${_v}[[:space:]]*(#.*)?$"; then
      :
    elif printf '%s\n' "$_block" | grep -Eq "^[[:space:]]*#[[:space:]]*${_k}[[:space:]]*="; then
      _say "cfg-${_k}" "DRIFT: managed key ${_k} is commented out in the block (manual disable?) -- re-run install-atuin-config.sh or edit deliberately"
      _drift=1
    else
      _say "cfg-${_k}" "DRIFT: managed key ${_k} = ${_v} missing from the block"
      _drift=1
    fi
  done
else
  _say cfg-block "DRIFT: managed [daemon] block markers missing from $_cfg -- re-run install-atuin-config.sh"
  _drift=1
fi

# Duplicate [daemon] keys outside the managed block: TOML duplicate keys
# break atuin's config parse entirely.
_dupes="$(awk '
  /^# atuin-daemon start/ { inblk = 1 }
  /^# atuin-daemon end/ { inblk = 0; next }
  /^[[:space:]]*\[daemon\]/ { ind = 1; next }
  /^[[:space:]]*\[/ { ind = 0 }
  ind && !inblk && $0 ~ /^[[:space:]]*(enabled|autostart|systemd_socket)[[:space:]]*=/ { print }
' "$_cfg" 2>/dev/null)"
if [ -n "$_dupes" ]; then
  _say cfg-dupe "DRIFT: unmanaged [daemon] key(s) outside the block (TOML duplicate keys break parsing):"
  printf '%s\n' "$_dupes" | sed 's/^/             /'
  _drift=1
else
  _say cfg-dupe "OK: no unmanaged [daemon] keys"
fi

# --- daemon identity + health ------------------------------------------------------
_pidfile="$_datadir/atuin-daemon.pid"
_cfg_pid="$(awk '
  /^[[:space:]]*\[daemon\]/ { ind = 1; next }
  /^[[:space:]]*\[/ { ind = 0 }
  ind && $0 ~ /^[[:space:]]*pidfile_path[[:space:]]*=/ {
    sub(/^[[:space:]]*pidfile_path[[:space:]]*=[[:space:]]*/, "")
    gsub(/"/, ""); print; exit
  }' "$_cfg" 2>/dev/null)"
[ -n "$_cfg_pid" ] && _pidfile="$_cfg_pid"

_svc_state="$(systemctl --user is-active "${_ubase}.service" 2>/dev/null || true)"
if [ "$_svc_state" = active ]; then
  _mainpid="$(systemctl --user show "${_ubase}.service" -p MainPID --value 2>/dev/null || echo 0)"
  if [ -r "$_pidfile" ]; then
    _dpid="$(sed -n '1p' "$_pidfile" | tr -dc '0-9')"
    # Pidfile formats: atuin >= 18.23 writes pid / "v1" marker / JSON
    # info line ({"version":...,"socket_path":...}); older daemons wrote
    # the bare version string on line 2. Parse both.
    _pf2="$(sed -n '2p' "$_pidfile" | tr -d '\r')"
    if [ "$_pf2" = "v1" ]; then
      _dver="$(sed -n '3p' "$_pidfile" | tr -d '\r' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    else
      _dver="$_pf2"
    fi
    if [ -n "$_dpid" ] && kill -0 "$_dpid" 2>/dev/null && [ "$(cat "/proc/$_dpid/comm" 2>/dev/null)" = atuin ]; then
      if [ "$_dpid" = "$_mainpid" ]; then
        _say daemon "OK: pid $_dpid matches unit MainPID"
      else
        _say daemon "DRIFT: pidfile pid $_dpid != unit MainPID ${_mainpid:-?} (foreign daemon?)"
        _drift=1
      fi
      _cli_ver="$("$_atbin" --version 2>/dev/null | awk '{print $2}')"
      if [ -n "$_dver" ] && [ -n "$_cli_ver" ] && [ "$_dver" != "$_cli_ver" ]; then
        _say version "DRIFT: daemon $_dver != CLI $_cli_ver -- systemctl --user restart ${_ubase}.service"
        _drift=1
      else
        _say version "OK: daemon and CLI at ${_dver:-$_cli_ver}"
      fi
    else
      _say daemon "DRIFT: pidfile content '${_dpid:-empty}' is not a live atuin process"
      _drift=1
    fi
  else
    _say daemon "DRIFT: service active but no pidfile at $_pidfile"
    _drift=1
  fi
  # Daemon already running: probing through the socket cannot trigger
  # activation, so `atuin daemon status` is side-effect free here.
  if _st="$("$_atbin" daemon status 2>&1)"; then
    _healthy="$(printf '%s\n' "$_st" | sed -n 's/^ *Healthy: *//p')"
    if [ "$_healthy" = true ]; then
      _say health "OK: daemon reports healthy"
    else
      _say health "DRIFT: daemon reports Healthy: ${_healthy:-unknown}"
      _drift=1
    fi
  else
    _say health "DRIFT: 'atuin daemon status' failed against the managed socket"
    _drift=1
  fi
else
  # Idle socket-activated state is valid -- but a socket file held while our
  # unit is INACTIVE means a foreign daemon (or stale file) the unit cannot
  # bind through.
  if [ "$_emergency" = 1 ] && [ "$_sock_state" != active ]; then
    _say daemon "OK: stopped by emergency mode"
  elif [ "$_sock_state" != active ] && [ -S "$_exp_sock" ]; then
    _say daemon "DRIFT: service inactive but $_exp_sock exists -- stale socket from an unclean shutdown; the socket unit cannot bind through it (fix: rm -f $_exp_sock; systemctl --user start ${_ubase}.socket)"
    _drift=1
  else
    _say daemon "OK: idle (socket-activated; starts on the first history hook)"
  fi
fi

# --- linger (informational) ---------------------------------------------------------
# Not drift: the history daemon is only useful during sessions. Linger adds
# continuous sync between logins; enabling needs polkit/root.
if command -v loginctl >/dev/null 2>&1; then
  if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" = yes ]; then
    _say linger "info: on (daemon syncs from boot, before first login)"
  else
    _say linger "info: off (daemon runs from first login; loginctl enable-linger for continuous sync)"
  fi
fi

# --- interactive search routing (informational) ---------------------------------------
# search_mode is a top-level key (before the first [section]).
_sm="$(awk '/^[[:space:]]*\[/ { exit } /^[[:space:]]*search_mode[[:space:]]*=/ { sub(/^[[:space:]]*search_mode[[:space:]]*=[[:space:]]*/, ""); gsub(/"/, ""); print; exit }' "$_cfg" 2>/dev/null)"
if [ "$_sm" = daemon-fuzzy ]; then
  _say search "info: search_mode daemon-fuzzy (interactive search rides the daemon's hot index; managed via ATUIN_SEARCH_MODE)"
else
  _say search "info: search_mode ${_sm:-<default>}; to point interactive search at the daemon set ATUIN_SEARCH_MODE=daemon-fuzzy and re-run install-atuin-config.sh"
fi

exit "$_drift"
