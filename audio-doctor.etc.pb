---
- hosts: all
  vars:
    TYPE: audio-doctor
    INSTANCE: main
    BINS:
      - name: audio-doctor
        global: true
        exec: |
          #!/bin/sh
          # audio-doctor: read-only diagnosis of the PipeWire audio stack.
          # Examines services, kernel log, graph topology, and whether the
          # graph actually consumes audio. Changes nothing. Companion:
          # audio-recover runs the escalation ladder.
          set -u
          FLAG=0
          hr(){ printf '\n== %s\n' "$*"; }

          hr "user services"
          for s in pipewire pipewire-pulse wireplumber pw-loopback filter-chain; do
            printf '  %-16s %s\n' "$s" "$(systemctl --user is-active "$s" 2>/dev/null || echo unknown)"
          done

          hr "defaults"
          if ! pactl info 2>/dev/null | grep -E 'Default (Sink|Source)'; then
            echo "  FLAG: pactl cannot reach the server (pipewire-pulse dead or XDG_RUNTIME_DIR unset?)"
            FLAG=1
          fi

          hr "kernel audio errors (last 6h)"
          if klog=$(journalctl -k --since -6h --no-pager 2>/dev/null | grep -iE 'usb_set_interface|not enough bandwidth|snd_.*error|alsa.*(error|timeout)|card removed' | tail -5) && [ -n "$klog" ]; then
            printf '%s\n' "$klog" | sed 's/^/  /'
            echo "  FLAG: kernel-level audio faults present (USB bandwidth / device resets)"
            FLAG=1
          else
            echo "  none"
          fi

          hr "error-state nodes"
          errs=$(pw-dump 2>/dev/null | jq -r '.[] | select(.type=="PipeWire:Interface:Node") | select(.info.state=="error") | .info.props["node.name"] // "?"')
          if [ -n "$errs" ]; then
            printf '%s\n' "$errs" | sed 's/^/  /'
            echo "  FLAG: nodes in error state wedge their whole driver group"
            FLAG=1
          else
            echo "  none"
          fi

          hr "graph driver concentration"
          pw-dump 2>/dev/null | jq -r '
            .[] | select(.type=="PipeWire:Interface:Node")
            | select(.info.props["media.class"]=="Audio/Sink")
            | "  sink " + (.info.props["node.name"]//"?") + " driven by " + ((.info.props["node.driver-id"]//"self")|tostring)' | sort || true
          srcdrv=$(pw-dump 2>/dev/null | jq -r '
            .[] | select(.type=="PipeWire:Interface:Node")
            | select(.info.props["media.class"]=="Audio/Source")
            | select(.info.props["node.driver"] == true)
            | select((.info.props["node.driver-id"]//"") == "")
            | "  capture " + (.info.props["node.name"]//"?") + " is a graph driver"' | sort -u || true)
          if [ -n "$srcdrv" ]; then
            printf '%s\n' "$srcdrv"
            echo "  NOTE: a capture device drives the playback graph (pw-loopback chains it in)."
            echo "  If it wedges, all output silences while everything shows RUNNING."
          fi

          hr "volumes / mutes (sinks)"
          pactl list sinks 2>/dev/null | grep -E '^	Name:|	Mute:|	Volume: front' | sed 's/^/  /'

          hr "flow test (1s tone to default sink)"
          defsink=$(pactl info 2>/dev/null | awk '/Default Sink/{print $3}')
          tone=$(mktemp /tmp/audio-doctor.XXXXXX)
          python3 - "$tone" <<'PY'
          import wave, math, struct, sys
          sr = 48000
          w = wave.open(sys.argv[1], 'w'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
          frames = []
          for i in range(sr):
              v = int(20000 * math.sin(2 * math.pi * 440 * i / sr))
              frames.append(struct.pack('<hh', v, v))
          w.writeframes(b''.join(frames)); w.close()
          PY
          timeout 4 pw-cat -p --target "${defsink:-combine_sink}" "$tone" >/dev/null 2>&1
          rc=$?
          rm -f "$tone"
          case $rc in
            0) echo "  OK: graph consumed the tone (exit 0)."
               echo "  If it is still inaudible: check physical chain (amps/DAC power),"
               echo "  then per-device volumes, then drop-in changes (empty update-props"
               echo "  rules cause running-but-silent sinks; see AUDIO-NOTES.md)." ;;
            124) echo "  FLAG: playback STALLED (timeout) - graph wedged. Run audio-recover."
                 FLAG=1 ;;
            *) echo "  FLAG: playback failed with exit $rc."; FLAG=1 ;;
          esac

          hr "verdict"
          if [ $FLAG -eq 0 ]; then
            echo "  No faults detected by automated checks."
          else
            echo "  Faults flagged above. Escalate with: audio-recover"
          fi
          exit $FLAG
      - name: audio-recover
        global: true
        exec: |
          #!/bin/sh
          # audio-recover: escalation ladder for wedged audio.
          #   1 suspend-cycle sources + restart pw-loopback
          #   2 USB rebind of the WEILIANG DAC (1-3) if present
          #   3 PCI rebind of the HD-Audio capture (0000:0b:00.4)
          #   4 full stack restart (wireplumber pipewire pipewire-pulse)
          # Each step is followed by a tone flow test; stops on first success.
          # Steps 2-3 need passwordless sudo. Closing pavucontrol is intentional:
          # its meters pin sources open and block suspend-based recovery.
          set -u
          USB_WEILIANG=1-3
          PCI_HDA=0000:0b:00.4
          hr(){ printf '\n== %s\n' "$*"; }

          flow() {
            defsink=$(pactl info 2>/dev/null | awk '/Default Sink/{print $3}')
            t=$(mktemp /tmp/audio-recover.XXXXXX)
            python3 - "$t" <<'PY'
          import wave, math, struct, sys
          sr = 48000
          w = wave.open(sys.argv[1], 'w'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
          frames = []
          for i in range(sr):
              v = int(20000 * math.sin(2 * math.pi * 440 * i / sr))
              frames.append(struct.pack('<hh', v, v))
          w.writeframes(b''.join(frames)); w.close()
          PY
            timeout 4 pw-cat -p --target "${defsink:-combine_sink}" "$t" >/dev/null 2>&1
            rc=$?
            rm -f "$t"
            [ $rc -eq 0 ]
          }

          hr "audio-recover: escalation ladder"
          pkill -x pavucontrol 2>/dev/null && echo "closed pavucontrol (meters pin sources open)"

          if flow; then hr "audio already flows; nothing to do"; exit 0; fi

          hr "step 1: suspend-cycle sources + restart pw-loopback"
          systemctl --user stop pw-loopback 2>/dev/null
          for s in $(pactl list short sources 2>/dev/null | awk '{print $2}' | grep -v '\.monitor$'); do
            pactl suspend-source "$s" 1 2>/dev/null; sleep 1
            pactl suspend-source "$s" 0 2>/dev/null
          done
          systemctl --user start pw-loopback 2>/dev/null
          sleep 2
          if flow; then hr "FIXED at step 1 (suspend cycle)"; exit 0; fi

          hr "step 2: USB rebind of WEILIANG ($USB_WEILIANG)"
          if [ -e "/sys/bus/usb/devices/$USB_WEILIANG" ]; then
            if sudo -n true 2>/dev/null; then
              echo "$USB_WEILIANG" | sudo -n tee /sys/bus/usb/drivers/usb/unbind >/dev/null
              sleep 2
              echo "$USB_WEILIANG" | sudo -n tee /sys/bus/usb/drivers/usb/bind >/dev/null
              sleep 3
              if flow; then hr "FIXED at step 2 (USB rebind)"; exit 0; fi
            else
              echo "  passwordless sudo unavailable; skipping rebind"
            fi
          else
            echo "  device not present; skipping"
          fi

          hr "step 3: PCI rebind of HD-Audio capture ($PCI_HDA)"
          if sudo -n true 2>/dev/null; then
            drv=$(basename "$(readlink "/sys/bus/pci/devices/$PCI_HDA/driver" 2>/dev/null)" 2>/dev/null)
            if [ -n "$drv" ]; then
              echo "$PCI_HDA" | sudo -n tee "/sys/bus/pci/drivers/$drv/unbind" >/dev/null
              sleep 3
              echo "$PCI_HDA" | sudo -n tee "/sys/bus/pci/drivers/$drv/bind" >/dev/null
              sleep 5
              systemctl --user restart pw-loopback 2>/dev/null
              if flow; then hr "FIXED at step 3 (PCI rebind; the 2026-10-15 fix)"; exit 0; fi
            else
              echo "  cannot determine driver for $PCI_HDA; skipping"
            fi
          else
            echo "  passwordless sudo unavailable; skipping rebind"
          fi

          hr "step 4: full stack restart"
          systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null
          sleep 4
          systemctl --user restart pw-loopback 2>/dev/null
          sleep 2
          if flow; then hr "FIXED at step 4 (stack restart)"; exit 0; fi

          hr "NOT FIXED"
          echo "  Reboot, then capture: audio-doctor output, kernel log around the"
          echo "  failure, and ~/.config/wireplumber/wireplumber.conf.d/ contents."
          echo "  Record findings in wireplumber-profile's AUDIO-NOTES.md incident log."
          exit 1
  tasks:
    - import_tasks: tasks/compfuzor.includes
