#!/usr/bin/env bash
# restart-clients.sh — fully restart every OpenCode *client* on this host
# while leaving the managed server alone (bin/restart.sh owns that side).
#
# Restarting a client means: kill the client process, wait for its tmux pane
# to fall back to the shell, then type
#   cd <recorded cwd> && opencode --session <recorded session id>
# into the pane with tmux send-keys. The pane's client-env ZIM module exports
# OPENCODE_ARGS, so the relaunched client attaches to the
# managed deployment exactly like a manual relaunch would. No `cd` is sent
# by default: the pane shell is normally still in the directory the client
# was launched from; when the shell's path has drifted from the recorded
# cwd the drift is reported (a cd-prefixed form is kept commented inside
# relaunch_client).
#
# Subcommands:
#   record    snapshot live clients into the state file and exit
#   list      print the recorded state with liveness annotations
#   clear     remove the state file (forget the registry)
#   kill      record, then kill every client (TERM, 20s grace, then KILL)
#             and sweep orphans; the registry stays for a later relaunch.
#             The server is not touched: restart it in this window
#             (bin/restart.sh), then bring the clients back with relaunch.
#   relaunch  relaunch every registry entry in its recorded pane, without
#             re-recording (the clients are dead; a fresh scan would find
#             nothing)
#   restart   (default) one-pass kill + relaunch, for client-only churn
#             when the server is current and builds match
#
# Full-restart sequence (server and clients both):
#   restart-clients.sh kill && bin/restart.sh && restart-clients.sh relaunch
#
# Options (position-independent):
#   -n, --dry-run   print what would happen; kill and send nothing, and
#                   leave the state file unwritten
#   -h, --help      this help
#
# The registry lives in memory (tmpfs), never on disk config:
#   ${XDG_RUNTIME_DIR:-/run/user/<uid>}/opencode/clients.tsv
# One TSV row per client: pid, opencode session id, tmux session:win.pane
# label, pane id, cwd, and exe. Session ids come from `cotail find-id <pid>
# --id-only` — the only working resolver: client processes never carry
# OPENCODE_SESSION_ID in their environ (that env is injected into tool
# shells by the opencode-shell-sessionids plugin, never into the TUIs).
# It is runtime truth only — wiped at logout/reboot, re-recordable any time.
#
# What is never touched: the managed server unit's MainPID and any process
# running `serve`; server-spawned tool shells (they are not pane
# descendants); this script's own process tree. Only root clients (the
# topmost opencode process of a tree) are recorded, so helper children
# (opencode2-node and friends) never duplicate their parent's pane.
# Clients with no resolvable session id, or whose pane is gone or showing
# another foreground program at relaunch time, are killed but left as a
# plain shell with a warning.
#
# Caveats:
#   * Relaunch rides the pane's *current* client environment (managed build).
#     If the running server lags the deployed client — the exe drift that
#     status.sh's exe-current reporter flags — one-pass restart reconnects
#     clients to a server they cannot talk to. Use the split sequence
#     instead (kill, bin/restart.sh, relaunch) so clients come back only
#     after the server is current. Dated-snapshot clients are likewise
#     resumed through the managed `opencode` command, not their original binary.
#   * Session resolution is cotail find-id: cwd match + most recently
#     updated session. A freshly launched TUI that never ran a prompt has
#     no session of its own and can associate with a different recently
#     active session in the same directory.
#
# Re-running restart after an interrupted run is safe; the state file is
# re-recorded from live processes each run, so an already-relaunched client
# may be restarted one extra time before converging.
#
# Env: OPENCODE_UNIT (server unit to spare, default opencode.service),
#      OPENCODE_CLIENTS_STATE (state file override),
#      OPENCODE_RESTART_CLIENTS_MAX_IDLE (idle gate, default 5d; sessions
#      whose last activity — cotail's timeIdle/timeUpdated — is older are
#      not relaunched; 0 disables the gate).
#
# Exit codes: 0 clean, 1 warnings were printed, 2 usage.

set -euo pipefail

self=$$
unit="${OPENCODE_UNIT:-opencode.service}"
state_file="${OPENCODE_CLIENTS_STATE:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/opencode/clients.tsv}"

dry_run=0
cmd=restart
warned=0

say() { printf '%s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; warned=1; }

usage() {
  cat <<'EOF'
usage: restart-clients.sh [record|list|clear|kill|relaunch|restart] [-n|--dry-run]

Restart every OpenCode client without touching the managed server.
Default subcommand: restart. The client registry is kept in tmpfs at
${XDG_RUNTIME_DIR:-/run/user/<uid>}/opencode/clients.tsv.

  record    snapshot live clients (pid, session id, tmux pane, cwd, exe)
  list      print the registry with liveness annotations
  clear     remove the registry file
  kill      record then kill every client (TERM, 20s grace, then KILL);
            registry kept — restart the server now, then `relaunch`
  relaunch  relaunch every registry entry in its recorded pane via
            `opencode --session <id>` (no cd; drift from the pane shell's
            cwd is reported)
  restart   one-pass kill + relaunch (server current, builds matching)
  -n        dry run: print actions only

Full-restart sequence (server and clients both):
  restart-clients.sh kill && bin/restart.sh && restart-clients.sh relaunch

Sessions idle longer than OPENCODE_RESTART_CLIENTS_MAX_IDLE (default 5d)
are not relaunched; 0 disables the gate.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    record|list|clear|kill|relaunch|restart) cmd=$1 ;;
    -n|--dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'restart-clients.sh: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# ------------------------------------------------------------- idle gate

max_idle="${OPENCODE_RESTART_CLIENTS_MAX_IDLE:-5d}"
idle_ms=0

duration_to_ms() {
  # "5d" / "72h" / "30m" / "432000s" / plain seconds -> milliseconds
  local v=$1 n=0 s=0
  case $v in
    *d) n=${v%d}; s=$((n * 86400)) ;;
    *h) n=${v%h}; s=$((n * 3600)) ;;
    *m) n=${v%m}; s=$((n * 60)) ;;
    *s) n=${v%s}; s=$n ;;
    *) n=$v; s=$n ;;
  esac
  case $n in
    ''|*[!0-9]*)
      printf 'restart-clients.sh: bad OPENCODE_RESTART_CLIENTS_MAX_IDLE: %s\n' "$v" >&2
      return 1
      ;;
  esac
  printf '%s' $((s * 1000))
}

if [ "$max_idle" != 0 ]; then
  idle_ms=$(duration_to_ms "$max_idle") || exit 2
fi

session_last_active_ms() {
  # newest of cotail's activity epochs for the session (epoch ms); empty
  # when unknown (cotail missing, session not found, parse failure)
  local sid=$1 json t_idle t_updated
  command -v cotail >/dev/null 2>&1 || { printf ''; return 0; }
  json=$(cotail find-id --session "$sid" --json 2>/dev/null | head -1 || true)
  [ -n "$json" ] || { printf ''; return 0; }
  t_idle=$(printf '%s' "$json" | sed -n 's/.*"timeIdle":\([0-9][0-9]*\).*/\1/p')
  t_updated=$(printf '%s' "$json" | sed -n 's/.*"timeUpdated":\([0-9][0-9]*\).*/\1/p')
  if [ -n "$t_idle" ] && [ -n "$t_updated" ]; then
    if [ "$t_idle" -gt "$t_updated" ]; then printf '%s' "$t_idle"
    else printf '%s' "$t_updated"; fi
  else
    printf '%s' "${t_idle:-$t_updated}"
  fi
}

# ---------------------------------------------------------------- helpers

quote() {
  # single-quote for the pane's zsh: ' -> '\''
  local q=${1//\'/\'\\\'\'}
  printf "'%s'" "$q"
}

proc_ppid() { sed -n 's/^PPid:[[:space:]]*//p' "/proc/$1/status" 2>/dev/null | head -1; }
proc_alive() { kill -0 "$1" 2>/dev/null; }

is_ancestor_of_self() {
  local target=$1 p=$self pp
  if [ "$target" = "$self" ]; then return 0; fi
  for _ in $(seq 16); do
    pp=$(proc_ppid "$p" || true)
    if [ -z "$pp" ] || [ "$pp" -le 1 ]; then return 1; fi
    if [ "$pp" = "$target" ]; then return 0; fi
    p=$pp
  done
  return 1
}

is_descendant_of_self() {
  local target=$1
  local p=$target pp
  if [ "$target" = "$self" ]; then return 0; fi
  for _ in $(seq 16); do
    pp=$(proc_ppid "$p" || true)
    if [ -z "$pp" ] || [ "$pp" -le 1 ]; then return 1; fi
    if [ "$pp" = "$self" ]; then return 0; fi
    p=$pp
  done
  return 1
}

# ---------------------------------------------------------------- tmux map

declare -A pane_by_shell_pid=()
declare -A label_by_pane=()

load_panes() {
  pane_by_shell_pid=()
  label_by_pane=()
  if ! command -v tmux >/dev/null 2>&1; then return 0; fi
  local fmt=$'#{pane_id}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}'
  local pane session widx pidx shell
  while IFS=$'\t' read -r pane session widx pidx shell; do
    [ -n "$pane" ] || continue
    pane_by_shell_pid[$shell]=$pane
    label_by_pane[$pane]="$session:$widx.$pidx"
  done < <(tmux list-panes -a -F "$fmt" 2>/dev/null || true)
}

pane_of() {
  # tmux pane hosting pid (through its ancestor shells); empty when the
  # process is not under tmux (console client, server tool shell, ...)
  local p=$1 pp
  for _ in $(seq 16); do
    if [ -n "${pane_by_shell_pid[$p]:-}" ]; then
      printf '%s' "${pane_by_shell_pid[$p]}"
      return 0
    fi
    pp=$(proc_ppid "$p" || true)
    if [ -z "$pp" ] || [ "$pp" -le 1 ]; then return 1; fi
    p=$pp
  done
  return 1
}

pane_alive() {
  tmux display-message -p -t "$1" '#{pane_id}' 2>/dev/null | grep -q .
}

wait_pane_shell() {
  # wait until the pane's foreground is a shell again; never type a
  # relaunch command into some other program the user put in the pane
  local pane=$1 i cur=""
  for i in $(seq 20); do
    cur=$(tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || true)
    case $cur in
      zsh|bash|fish|sh|dash|ksh) sleep 0.4; return 0 ;;
      "") return 1 ;;
    esac
    sleep 0.25
  done
  warn "pane $pane foreground stayed '${cur:-?}'; not typing into it"
  return 1
}

# ------------------------------------------------------------ process scan

server_pid="$(systemctl --user show "$unit" -p MainPID --value 2>/dev/null || true)"
case $server_pid in ''|0|'[not'*) server_pid=0 ;; esac

declare -A oc_pids=()
declare -A oc_ppid=()
declare -A oc_args=()

scan_processes() {
  oc_pids=(); oc_ppid=(); oc_args=()
  local pid ppid comm args
  while read -r pid ppid comm args; do
    [ -n "$pid" ] || continue
    oc_pids[$pid]=1
    oc_ppid[$pid]=$ppid
    oc_args[$pid]=${args:-}
  done < <(ps -eo pid=,ppid=,comm=,args= 2>/dev/null | awk '$3 ~ /^opencode/ {print}' || true)
}

is_server_process() {
  if [ "$1" = "$server_pid" ] && [ "$server_pid" != 0 ]; then return 0; fi
  case $2 in
    *" serve "*|*" serve") return 0 ;;
  esac
  return 1
}

is_tui_argv() {
  # plain TUI launches only: root flags plus at most a directory positional.
  # Anything with a subcommand (api, run, --version, completions, ...) is a
  # transient or non-interactive client: killed by the sweep, never
  # relaunched into its pane.
  local -a tok
  read -r -a tok <<<"$1"
  local i=0 n=${#tok[@]}
  while [ "$i" -lt "$n" ]; do
    case ${tok[$i]} in
      --server|--session|-s|--prompt|--log-level|--completions) i=$((i + 2)) ;;
      --server=*|--session=*|--prompt=*|--log-level=*|--completions=*) i=$((i + 1)) ;;
      --standalone|--print-logs|--wizard|--auto|--continue|-c) i=$((i + 1)) ;;
      --) return 1 ;;
      -*) i=$((i + 1)) ;;
      *)
        # first positional: the TUI takes a directory here, nothing else
        case ${tok[$i]} in
          /*|*/*|.|..) return 0 ;;
          *) return 1 ;;
        esac
        ;;
    esac
  done
  return 0
}

session_of() {
  # cotail is the only working resolver (FX-checked: no opencode client
  # process carries OPENCODE_SESSION_ID in its environ — that env only
  # reaches tool shells via the opencode-shell-sessionids plugin — and an
  # inherited stale value would silently record the wrong session)
  local pid=$1 sid=""
  if command -v cotail >/dev/null 2>&1; then
    sid=$(cotail find-id "$pid" --id-only 2>/dev/null || true)
  fi
  case $sid in
    ses_*) printf '%s' "$sid" ;;
    *) printf '' ;;
  esac
}

sanitize() { printf '%s' "$1" | tr -d '\t\n\r'; }

# ---------------------------------------------------------------- record

record_lines=""
record_count=0

do_record() {
  load_panes
  scan_processes
  record_lines=""
  record_count=0
  local pid ppid pane sid cwd exe label
  for pid in "${!oc_pids[@]}"; do
    ppid=${oc_ppid[$pid]}
    # root clients only: helper children would duplicate their parent's pane
    if [ -n "${oc_pids[$ppid]:-}" ]; then continue; fi
    # spare the managed server and anything running serve
    if is_server_process "$pid" "${oc_args[$pid]}"; then continue; fi
    # spare this script's own tree; its transient children look like clients
    if [ "$pid" = "$self" ] || is_descendant_of_self "$pid"; then continue; fi
    # only plain TUI argv shapes are recorded; transients go to the sweep
    if ! is_tui_argv "${oc_args[$pid]}"; then continue; fi
    pane=$(pane_of "$pid" || true)
    sid=$(session_of "$pid")
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
    if [ -n "$pane" ]; then label=${label_by_pane[$pane]:-}; else label="-"; fi
    record_lines+="$(sanitize "$pid")$(printf '\t')$(sanitize "$sid")$(printf '\t')$(sanitize "$label")$(printf '\t')$(sanitize "$pane")$(printf '\t')$(sanitize "$cwd")$(printf '\t')$(sanitize "$exe")
"
    record_count=$((record_count + 1))
    printf 'recorded %s sid=%s pane=%s label=%s cwd=%s\n' \
      "$pid" "${sid:--}" "${pane:--}" "$label" "${cwd:--}"
  done
  if [ "$dry_run" = 1 ]; then
    say "dry-run: $record_count client(s) would be recorded to $state_file"
    return 0
  fi
  mkdir -p "$(dirname "$state_file")"
  local tmp="$state_file.tmp.$$"
  {
    printf '# opencode client registry — runtime truth in tmpfs, written by restart-clients.sh\n'
    printf '# fields: pid session_id tmux_label pane_id cwd exe\n'
    printf '%s' "$record_lines"
  } > "$tmp"
  mv -f "$tmp" "$state_file"
  say "recorded $record_count client(s) -> $state_file"
}

# ----------------------------------------------------------------- state

declare -a r_pid=() r_sid=() r_label=() r_pane=() r_cwd=() r_exe=()

read_state_lines() {
  r_pid=(); r_sid=(); r_label=(); r_pane=(); r_cwd=(); r_exe=()
  local pid sid label pane cwd exe
  while IFS=$'\t' read -r pid sid label pane cwd exe; do
    case $pid in ''|'#'*) continue ;; esac
    r_pid+=("$pid"); r_sid+=("$sid"); r_label+=("$label")
    r_pane+=("$pane"); r_cwd+=("$cwd"); r_exe+=("$exe")
  done
}

read_state() {
  if [ ! -r "$state_file" ]; then
    warn "no state file at $state_file (run: record)"
    return 0
  fi
  read_state_lines < "$state_file"
}

# --------------------------------------------------------------- restart

kill_client() {
  local pid=$1 i
  if ! proc_alive "$pid"; then
    say "  pid $pid already gone"
    return 0
  fi
  if [ "$dry_run" = 1 ]; then
    say "  dry-run: would kill $pid"
    return 0
  fi
  kill -TERM "$pid" 2>/dev/null || true
  # 20s grace: the TUI saves state, closes its event stream, and repaints
  # the pane shell; TERM is the cooperative path, KILL is the fallback
  for i in $(seq 40); do
    if ! proc_alive "$pid"; then say "  killed $pid (TERM)"; return 0; fi
    sleep 0.5
  done
  kill -KILL "$pid" 2>/dev/null || true
  for i in $(seq 6); do
    if ! proc_alive "$pid"; then say "  killed $pid (KILL)"; return 0; fi
    sleep 0.5
  done
  warn "pid $pid survived SIGKILL"
}

sweep_skip() {
  # 0 (skip) when the pid is the server, this script's tree, an
  # already-handled recorded root, or not under any tmux pane
  local pid=$1 i
  if is_server_process "$pid" "${oc_args[$pid]:-}"; then return 0; fi
  if [ "$pid" = "$self" ] || is_descendant_of_self "$pid"; then return 0; fi
  for i in $(seq 0 $((${#r_pid[@]} - 1))); do
    if [ "${r_pid[$i]}" = "$pid" ]; then return 0; fi
  done
  if [ -z "$(pane_of "$pid" || true)" ]; then return 0; fi
  return 1
}

sweep_orphans() {
  # after the root clients died, kill any remaining pane-descendant
  # opencode processes the record/kill phases did not already own: orphaned
  # helpers and transient foreground clients. Never the recorded roots
  # (handled above), the server and its (non-pane) children, or this
  # script's tree.
  scan_processes
  load_panes
  local pid
  for pid in "${!oc_pids[@]}"; do
    if sweep_skip "$pid"; then continue; fi
    if proc_alive "$pid"; then
      say "sweep: killing pane-descendant $pid (${oc_args[$pid]:0:60})"
      if [ "$dry_run" = 1 ]; then continue; fi
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  if [ "$dry_run" = 1 ]; then return 0; fi
  sleep 1
  for pid in "${!oc_pids[@]}"; do
    if sweep_skip "$pid"; then continue; fi
    if proc_alive "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

relaunch_client() {
  local pid=$1 sid=$2 label=$3 pane=$4 cwd=$5
  if [ -z "$pane" ] || [ "$pane" = "-" ]; then
    warn "client $pid ($label): no tmux pane recorded; left killed, relaunch manually"
    return 0
  fi
  if ! pane_alive "$pane"; then
    warn "client $pid ($label): pane $pane is gone; relaunch manually in that window"
    return 0
  fi
  if [ -z "$sid" ]; then
    warn "client $pid ($label): no session id resolved (cotail find-id failed?); pane left at a shell"
    return 0
  fi

  # idle gate: a session untouched for longer than the threshold is not
  # worth resurrecting — leave the pane as a plain shell
  local last_ms age_ms
  if [ "$idle_ms" -gt 0 ]; then
    last_ms=$(session_last_active_ms "$sid")
    if [ -n "$last_ms" ]; then
      age_ms=$(($(date +%s%3N) - last_ms))
      if [ "$age_ms" -gt "$idle_ms" ]; then
        say "  skipped $label: session idle for $((age_ms / 86400000))d (gate ${max_idle}); pane left at a shell"
        return 0
      fi
    else
      say "  note: $label: cotail could not determine session age; gate not applied"
    fi
  fi

  # no cd: the pane shell is normally still where the client was launched
  # from. Detect drift against the recorded cwd and report it; the cd form
  # stays commented here for when forcing the directory matters.
  #   launch="cd $(quote "$cwd") && opencode --session $(quote "$sid")"
  local shell_path launch
  shell_path=$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null || true)
  if [ -n "$cwd" ] && [ -n "$shell_path" ] && [ "$shell_path" != "$cwd" ]; then
    say "  note: $label: pane cwd $shell_path != recorded $cwd (no cd sent)"
  fi
  launch="opencode --session $(quote "$sid")"

  if [ "$dry_run" = 1 ]; then
    say "  dry-run: would send to $label ($pane): $launch"
    return 0
  fi
  if ! wait_pane_shell "$pane"; then return 0; fi
  tmux send-keys -t "$pane" -l -- "$launch"
  tmux send-keys -t "$pane" C-m
  say "  relaunched in $label: $launch"
}

kill_phase() {
  # kill phase; the pane hosting this very session goes last: killing our
  # ancestor TUI (standalone mode only — server-hosted tool shells are
  # never pane descendants) can cut this script's output mid-run
  local n=${#r_pid[@]} i
  for i in $(seq 0 $((n - 1))); do
    if is_ancestor_of_self "${r_pid[$i]}"; then continue; fi
    say "client ${r_pid[$i]} (${r_label[$i]}) sid=${r_sid[$i]:-none}"
    kill_client "${r_pid[$i]}"
  done
  for i in $(seq 0 $((n - 1))); do
    if ! is_ancestor_of_self "${r_pid[$i]}"; then continue; fi
    say "NOTE: client ${r_pid[$i]} hosts this very session; killed last, output may end here"
    kill_client "${r_pid[$i]}"
  done
  sweep_orphans
}

relaunch_phase() {
  local n=${#r_pid[@]} i
  for i in $(seq 0 $((n - 1))); do
    relaunch_client "${r_pid[$i]}" "${r_sid[$i]}" "${r_label[$i]}" "${r_pane[$i]}" "${r_cwd[$i]}"
  done
}

do_kill() {
  # stop half of the full-restart sequence: clients die, the registry stays
  # for a later relaunch. The server is NOT touched here — restart it in
  # this window (bin/restart.sh), then bring the clients back.
  do_record
  read_state_lines <<<"$record_lines"
  local n=${#r_pid[@]}
  if [ "$n" -eq 0 ]; then
    say "no opencode clients found; nothing to kill"
    return 0
  fi
  say "killing $n client(s)"
  kill_phase
  if [ "$dry_run" = 1 ]; then return 0; fi
  say "clients down; server window: bin/restart.sh now, then: $(basename "$0") relaunch"
}

do_relaunch() {
  # bring half of the full-restart sequence: relaunch from the recorded
  # registry without re-recording (the clients are dead; a fresh scan
  # would find nothing)
  read_state
  local n=${#r_pid[@]}
  if [ "$n" -eq 0 ]; then
    say "registry empty; nothing to relaunch"
    return 0
  fi
  say "relaunching $n client(s) from registry"
  relaunch_phase
  say "done: $n client(s) processed"
}

do_restart() {
  # one-pass form for client-only churn (server current, builds matching);
  # the kill -> restart.sh -> relaunch split lives in kill/relaunch
  do_record
  read_state_lines <<<"$record_lines"
  local n=${#r_pid[@]}
  if [ "$n" -eq 0 ]; then
    say "no opencode clients found; nothing to restart"
    return 0
  fi
  say "restarting $n client(s)"
  kill_phase
  relaunch_phase
  say "done: $n client(s) processed"
}

# ------------------------------------------------------------------ list

do_clear() {
  if [ ! -e "$state_file" ]; then
    say "no state file at $state_file"
    return 0
  fi
  if [ "$dry_run" = 1 ]; then
    say "dry-run: would remove $state_file"
    return 0
  fi
  rm -f -- "$state_file"
  say "cleared $state_file"
}

do_list() {
  if [ ! -r "$state_file" ]; then
    warn "no state file at $state_file (run: record)"
    return 0
  fi
  read_state
  local n=${#r_pid[@]} i pid st pst
  say "state: $state_file"
  if [ "$n" -eq 0 ]; then
    say "(empty)"
    return 0
  fi
  printf '%-9s %-6s %-8s %-26s %s\n' PID STATE PANE SESSION CWD
  for i in $(seq 0 $((n - 1))); do
    pid=${r_pid[$i]}
    if proc_alive "$pid"; then st=alive; else st=dead; fi
    if [ -n "${r_pane[$i]}" ] && [ "${r_pane[$i]}" != "-" ] && pane_alive "${r_pane[$i]}"; then
      pst=pane-ok
    else
      pst=no-pane
    fi
    printf '%-9s %-6s %-8s %-26s %s\n' "$pid" "$st" "$pst" "${r_sid[$i]:-?}" "${r_cwd[$i]:-?} (${r_label[$i]})"
  done
}

# ------------------------------------------------------------------ main

case $cmd in
  record) do_record ;;
  list) do_list ;;
  clear) do_clear ;;
  kill) do_kill ;;
  relaunch) do_relaunch ;;
  restart) do_restart ;;
esac

if [ "$warned" != 0 ]; then exit 1; fi
