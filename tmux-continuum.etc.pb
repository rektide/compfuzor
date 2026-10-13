---
- hosts: all
  vars:
    ETC_FILES:
      - name: 99-continuum.conf
        content: |
          # Requires tmux-resurrect. Install tmux-resurrect.etc.pb as well.
          # Keep Continuum last in the plugin list, after any status-line theme.
          set -g @plugin 'tmux-plugins/tmux-continuum'
          # Ahiru otherwise loads plugins in parallel, racing themes/Resurrect.
          set -g @tpm-parallel 'false'
          # Save periodically; restore only via Resurrect's restore-session.sh.
          set -g @continuum-restore 'off'
          set -g @continuum-save-interval '15'
          # Automatic saves require the tmux status line to remain enabled.
    BINS:
      - name: install-tmux.sh
        compose: False
        basedir: False
        content: |
          set -eu
          HOST=${1:?usage: install-tmux.sh HOST_DEPLOYMENT_DIR}
          exec "$HOST/bin/config-remote.mjs" put tmux/plugins "$DIR/etc/99-continuum.conf"
      - name: status.sh
        compose: False
        basedir: False
        content: |
          # Read-only health report for Continuum automatic saving on the
          # default-socket tmux server. Works inside or outside tmux.
          # Exit 0: saving machinery healthy. 1: not saving or degraded.
          # 2: nothing to inspect (no tmux server / binary).
          command -v tmux >/dev/null 2>&1 || { echo "status.sh: tmux not found" >&2; exit 2; }
          if ! tmux list-sessions >/dev/null 2>&1; then
            echo "status.sh: no running tmux server to report on" >&2
            exit 2
          fi

          option() { tmux show-option -gqv "$1"; }
          ago() {
            if [ "$1" -lt 60 ]; then printf '%ss' "$1"
            elif [ "$1" -lt 3600 ]; then printf '%sm' $(( $1 / 60 ))
            elif [ "$1" -lt 86400 ]; then printf '%sh %sm' $(( $1 / 3600 )) $(( $1 % 3600 / 60 ))
            else printf '%sd %sh' $(( $1 / 86400 )) $(( $1 % 86400 / 3600 ))
            fi
          }

          interval=$(option @continuum-save-interval)
          case "$interval" in ''|*[!0-9]*) interval=15 ;; esac  # plugin default
          restore=$(option @continuum-restore)
          [ -n "$restore" ] || restore=off
          last_save=$(option @continuum-save-last-timestamp)
          case "$last_save" in ''|*[!0-9]*) last_save='' ;; esac
          engine=$(option @resurrect-save-script-path)
          resurrect_dir=$(option @resurrect-dir)
          [ -n "$resurrect_dir" ] || resurrect_dir='~/.tmux/resurrect'
          resurrect_dir="${resurrect_dir/#\~/$HOME}"
          status_right=$(tmux show-option -gv status-right)
          status_line=$(tmux show-option -gv status)
          redraw=$(tmux show-option -gv status-interval)
          case "$redraw" in ''|*[!0-9]*) redraw=15 ;; esac
          sessions=$(tmux list-sessions -F x | wc -l | tr -d ' ')
          now=$(date +%s)
          problems=0

          attached=0
          case "$status_right" in *continuum_save.sh*) attached=1 ;; esac

          echo "server: $sessions session(s), status line $status_line, redraw every ${redraw}s"
          if [ "$attached" = 1 ]; then
            echo "save hook: attached (continuum_save.sh rides status-right redraws)"
          else
            problems=$((problems + 1))
            echo "save hook: MISSING from status-right" >&2
            echo "  continuum never attached: plugin not loaded, status-right replaced after" >&2
            echo "  it loaded, or another tmux server was already running then" >&2
          fi

          if [ "$interval" -gt 0 ]; then
            echo "auto-save: every ${interval}m"
          else
            problems=$((problems + 1))
            echo "auto-save: disabled (@continuum-save-interval is 0)" >&2
          fi

          if [ -n "$last_save" ]; then
            echo "last auto-save: $(ago $(( now - last_save ))) ago ($(date -d "@$last_save" '+%Y-%m-%d %H:%M:%S %Z'))"
          else
            echo "last auto-save: none recorded in this server"
          fi

          if [ "$interval" -gt 0 ] && [ -n "$last_save" ]; then
            due=$(( last_save + interval * 60 ))
            if [ "$now" -lt "$due" ]; then
              echo "next auto-save: in $(ago $(( due - now )))"
            elif [ $(( now - due )) -le $(( redraw * 2 + 60 )) ]; then
              echo "next auto-save: due now"
            else
              problems=$((problems + 1))
              echo "next auto-save: overdue by $(ago $(( now - due )))" >&2
              echo "  hook attached but not firing: status line hidden, machine asleep," >&2
              echo "  or server suspended since the last save" >&2
            fi
          fi

          if [ -n "$engine" ]; then
            if [ -x "$engine" ]; then
              echo "save engine: $engine"
            else
              problems=$((problems + 1))
              echo "save engine: $engine not executable" >&2
            fi
          else
            problems=$((problems + 1))
            echo "save engine: unset (@resurrect-save-script-path); initialize tmux-resurrect" >&2
          fi

          snapshot=$resurrect_dir/last
          if [ -e "$snapshot" ]; then
            resolved=$(readlink -f -- "$snapshot")
            echo "last snapshot: $(basename "$resolved") (written $(date -r "$resolved" '+%Y-%m-%d %H:%M'))"
          else
            echo "last snapshot: none yet under $resurrect_dir"
          fi
          echo "restore-on-start: $restore (explicit restore: resurrect bin/restore-session.sh)"

          if [ "$attached" = 1 ] && [ "$status_line" != "on" ]; then
            problems=$((problems + 1))
            echo "status line off: the attached hook only fires on status redraws" >&2
          fi

          if [ "$problems" -eq 0 ]; then
            summary="continuum: saving every ${interval}m"
            if [ -n "$last_save" ]; then
              summary="$summary, last saved $(ago $(( now - last_save ))) ago"
            fi
            echo "$summary"
          else
            echo "continuum: NOT saving ($problems problem(s) above)" >&2
            exit 1
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
