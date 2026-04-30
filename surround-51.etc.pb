---
- hosts: all
  vars:
    TYPE: surround-51
    INSTANCE: main
    ETC_FILES:
      - name: surround-51-lfe-only.conf
        content: |
          # 5.1 surround with dedicated LFE to subwoofer only.
          # Channel routing:
          #   FL + 0.4*FC -> Mpow R (front left speaker)
          #   FR + 0.4*FC -> FiiO L (front right speaker)
          #   RL          -> Mpow L (rear left speaker)
          #   RR          -> FiiO R (rear right speaker)
          #   LFE         -> SB X-Fi (subwoofer)
          #
          # After loading, run: surround-51-activate
          context.modules = [
            { name = libpipewire-module-filter-chain
              args = {
                node.description = "5.1 Surround (LFE only)"
                media.name       = "surround_51"
                filter.graph = {
                  nodes = [
                    { name = copy_FL  type = builtin label = copy }
                    { name = copy_FR  type = builtin label = copy }
                    { name = copy_FC  type = builtin label = copy }
                    { name = copy_RL  type = builtin label = copy }
                    { name = copy_RR  type = builtin label = copy }
                    { name = copy_LFE type = builtin label = copy }
                    { name = copy_FC2 type = builtin label = copy }
                    {
                      name   = mix_front_L
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                      }
                    }
                    {
                      name   = mix_front_R
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                      }
                    }
                  ]
                  links = [
                    { output = "copy_FL:Out"  input = "mix_front_L:In 1" }
                    { output = "copy_FC:Out"  input = "mix_front_L:In 2" }
                    { output = "copy_FR:Out"  input = "mix_front_R:In 1" }
                    { output = "copy_FC2:Out" input = "mix_front_R:In 2" }
                  ]
                  inputs = [
                    "copy_FL:In"
                    "copy_FR:In"
                    "copy_FC:In"
                    "copy_LFE:In"
                    "copy_RL:In"
                    "copy_RR:In"
                  ]
                  outputs = [
                    "mix_front_L:Out"
                    "mix_front_R:Out"
                    "copy_FC:Out"
                    "copy_LFE:Out"
                    "copy_RL:Out"
                    "copy_RR:Out"
                  ]
                }
                capture.props = {
                  node.name      = "surround_51_input"
                  media.class    = "Audio/Sink"
                  audio.channels = 6
                  audio.position = [ FL FR FC LFE RL RR ]
                }
                playback.props = {
                  node.name         = "surround_51_output"
                  audio.channels    = 6
                  audio.position    = [ FL FR FC LFE RL RR ]
                  stream.dont-remix = true
                  node.passive      = true
                }
              }
            }
          ]

      - name: surround-51-lfe-bass.conf
        content: |
          # 5.1 surround with LFE + bass extraction to subwoofer.
          # Same as lfe-only, but also extracts low frequencies from all channels
          # and mixes them into the subwoofer output.
          # Uses a 120Hz lowpass on the summed channels for bass extraction.
          context.modules = [
            { name = libpipewire-module-filter-chain
              args = {
                node.description = "5.1 Surround (LFE + bass to sub)"
                media.name       = "surround_51"
                filter.graph = {
                  nodes = [
                    { name = copy_FL  type = builtin label = copy }
                    { name = copy_FR  type = builtin label = copy }
                    { name = copy_FC  type = builtin label = copy }
                    { name = copy_RL  type = builtin label = copy }
                    { name = copy_RR  type = builtin label = copy }
                    { name = copy_LFE type = builtin label = copy }
                    { name = copy_FC2 type = builtin label = copy }
                    {
                      name   = mix_front_L
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                      }
                    }
                    {
                      name   = mix_front_R
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                      }
                    }
                    {
                      name   = mix_bass
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.5
                        "Gain 2" = 0.5
                        "Gain 3" = 0.5
                        "Gain 4" = 0.5
                        "Gain 5" = 0.5
                      }
                    }
                    {
                      name  = lp_bass
                      type  = builtin
                      label = bq_lowpass
                      control = { "Freq" = 120.0 "Q" = 0.707 }
                    }
                    {
                      name   = mix_sub
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 1.0
                        "Gain 2" = 1.0
                      }
                    }
                  ]
                  links = [
                    { output = "copy_FL:Out"  input = "mix_front_L:In 1" }
                    { output = "copy_FC:Out"  input = "mix_front_L:In 2" }
                    { output = "copy_FR:Out"  input = "mix_front_R:In 1" }
                    { output = "copy_FC2:Out" input = "mix_front_R:In 2" }
                    { output = "copy_FL:Out"  input = "mix_bass:In 1" }
                    { output = "copy_FR:Out"  input = "mix_bass:In 2" }
                    { output = "copy_FC:Out"  input = "mix_bass:In 3" }
                    { output = "copy_RL:Out"  input = "mix_bass:In 4" }
                    { output = "copy_RR:Out"  input = "mix_bass:In 5" }
                    { output = "copy_LFE:Out" input = "mix_sub:In 1" }
                    { output = "mix_bass:Out" input = "lp_bass:In" }
                    { output = "lp_bass:Out"  input = "mix_sub:In 2" }
                  ]
                  inputs = [
                    "copy_FL:In"
                    "copy_FR:In"
                    "copy_FC:In"
                    "copy_LFE:In"
                    "copy_RL:In"
                    "copy_RR:In"
                  ]
                  outputs = [
                    "mix_front_L:Out"
                    "mix_front_R:Out"
                    "copy_FC:Out"
                    "mix_sub:Out"
                    "copy_RL:Out"
                    "copy_RR:Out"
                  ]
                }
                capture.props = {
                  node.name      = "surround_51_input"
                  media.class    = "Audio/Sink"
                  audio.channels = 6
                  audio.position = [ FL FR FC LFE RL RR ]
                }
                playback.props = {
                  node.name         = "surround_51_output"
                  audio.channels    = 6
                  audio.position    = [ FL FR FC LFE RL RR ]
                  stream.dont-remix = true
                  node.passive      = true
                }
              }
            }
          ]

      - name: surround-51-no-sub.conf
        content: |
          # 5.1 surround without subwoofer.
          # LFE channel is mixed into the front speakers alongside center.
          # Front speakers get: 0.7*FL/FR + 0.4*FC + 0.3*LFE
          context.modules = [
            { name = libpipewire-module-filter-chain
              args = {
                node.description = "5.1 Surround (no sub)"
                media.name       = "surround_51"
                filter.graph = {
                  nodes = [
                    { name = copy_FL  type = builtin label = copy }
                    { name = copy_FR  type = builtin label = copy }
                    { name = copy_FC  type = builtin label = copy }
                    { name = copy_RL  type = builtin label = copy }
                    { name = copy_RR  type = builtin label = copy }
                    { name = copy_LFE type = builtin label = copy }
                    { name = copy_FC2 type = builtin label = copy }
                    { name = copy_LFE2 type = builtin label = copy }
                    {
                      name   = mix_front_L
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                        "Gain 3" = 0.3
                      }
                    }
                    {
                      name   = mix_front_R
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                        "Gain 3" = 0.3
                      }
                    }
                  ]
                  links = [
                    { output = "copy_FL:Out"   input = "mix_front_L:In 1" }
                    { output = "copy_FC:Out"   input = "mix_front_L:In 2" }
                    { output = "copy_LFE:Out"  input = "mix_front_L:In 3" }
                    { output = "copy_FR:Out"   input = "mix_front_R:In 1" }
                    { output = "copy_FC2:Out"  input = "mix_front_R:In 2" }
                    { output = "copy_LFE2:Out" input = "mix_front_R:In 3" }
                  ]
                  inputs = [
                    "copy_FL:In"
                    "copy_FR:In"
                    "copy_FC:In"
                    "copy_LFE:In"
                    "copy_RL:In"
                    "copy_RR:In"
                  ]
                  outputs = [
                    "mix_front_L:Out"
                    "mix_front_R:Out"
                    "copy_FC:Out"
                    "copy_LFE:Out"
                    "copy_RL:Out"
                    "copy_RR:Out"
                  ]
                }
                capture.props = {
                  node.name      = "surround_51_input"
                  media.class    = "Audio/Sink"
                  audio.channels = 6
                  audio.position = [ FL FR FC LFE RL RR ]
                }
                playback.props = {
                  node.name         = "surround_51_output"
                  audio.channels    = 6
                  audio.position    = [ FL FR FC LFE RL RR ]
                  stream.dont-remix = true
                  node.passive      = true
                }
              }
            }
          ]

      - name: surround-51-stereo-sub.conf
        content: |
          # 5.1 surround with stereo downmix sent to subwoofer.
          # Subwoofer gets a mono sum of FL+FR lowpassed at 120Hz.
          # LFE channel is also mixed in.
          # The X-Fi's own crossover will handle the final subwoofer filtering.
          context.modules = [
            { name = libpipewire-module-filter-chain
              args = {
                node.description = "5.1 Surround (stereo to sub)"
                media.name       = "surround_51"
                filter.graph = {
                  nodes = [
                    { name = copy_FL  type = builtin label = copy }
                    { name = copy_FR  type = builtin label = copy }
                    { name = copy_FC  type = builtin label = copy }
                    { name = copy_RL  type = builtin label = copy }
                    { name = copy_RR  type = builtin label = copy }
                    { name = copy_LFE type = builtin label = copy }
                    { name = copy_FC2 type = builtin label = copy }
                    {
                      name   = mix_front_L
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                      }
                    }
                    {
                      name   = mix_front_R
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.7
                        "Gain 2" = 0.4
                      }
                    }
                    {
                      name   = mix_sub
                      type   = builtin
                      label  = mixer
                      control = {
                        "Gain 1" = 0.5
                        "Gain 2" = 0.5
                        "Gain 3" = 1.0
                      }
                    }
                    {
                      name  = lp_sub
                      type  = builtin
                      label = bq_lowpass
                      control = { "Freq" = 120.0 "Q" = 0.707 }
                    }
                  ]
                  links = [
                    { output = "copy_FL:Out"  input = "mix_front_L:In 1" }
                    { output = "copy_FC:Out"  input = "mix_front_L:In 2" }
                    { output = "copy_FR:Out"  input = "mix_front_R:In 1" }
                    { output = "copy_FC2:Out" input = "mix_front_R:In 2" }
                    { output = "copy_FL:Out"  input = "mix_sub:In 1" }
                    { output = "copy_FR:Out"  input = "mix_sub:In 2" }
                    { output = "copy_LFE:Out" input = "mix_sub:In 3" }
                    { output = "mix_sub:Out"  input = "lp_sub:In" }
                  ]
                  inputs = [
                    "copy_FL:In"
                    "copy_FR:In"
                    "copy_FC:In"
                    "copy_LFE:In"
                    "copy_RL:In"
                    "copy_RR:In"
                  ]
                  outputs = [
                    "mix_front_L:Out"
                    "mix_front_R:Out"
                    "copy_FC:Out"
                    "lp_sub:Out"
                    "copy_RL:Out"
                    "copy_RR:Out"
                  ]
                }
                capture.props = {
                  node.name      = "surround_51_input"
                  media.class    = "Audio/Sink"
                  audio.channels = 6
                  audio.position = [ FL FR FC LFE RL RR ]
                }
                playback.props = {
                  node.name         = "surround_51_output"
                  audio.channels    = 6
                  audio.position    = [ FL FR FC LFE RL RR ]
                  stream.dont-remix = true
                  node.passive      = true
                }
              }
            }
          ]

    BINS:
      - name: surround-51-activate
        content: |
          #!/bin/bash
          set -euo pipefail

          MODE="${1:-lfe-only}"
          CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/pipewire.conf.d"
          ETC_DIR="$(cd "$(dirname "$0")/.." && pwd)/etc"

          case "$MODE" in
            lfe-only|lfe-bass|no-sub|stereo-sub)
              CONF_FILE="surround-51-${MODE}.conf"
              ;;
            off)
              rm -f "$CONF_DIR/surround-51.conf"
              echo "Surround 5.1 disabled. Restart PipeWire to apply."
              systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
              exit 0
              ;;
            *)
              echo "Usage: $(basename "$0") {lfe-only|lfe-bass|no-sub|stereo-sub|off}"
              echo ""
              echo "Modes:"
              echo "  lfe-only    LFE channel only to subwoofer"
              echo "  lfe-bass    LFE + extracted bass from all channels to subwoofer"
              echo "  no-sub      No subwoofer, LFE mixed into front speakers"
              echo "  stereo-sub  Stereo downmix + LFE to subwoofer"
              echo "  off         Disable surround 5.1"
              exit 1
              ;;
          esac

          if [ ! -f "$ETC_DIR/$CONF_FILE" ]; then
            echo "Error: config file $ETC_DIR/$CONF_FILE not found"
            exit 1
          fi

          mkdir -p "$CONF_DIR"
          ln -sfn "$ETC_DIR/$CONF_FILE" "$CONF_DIR/surround-51.conf"
          echo "Activated surround 5.1 mode: $MODE"
          echo "Restarting PipeWire..."
          systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

          echo "Waiting for PipeWire to stabilize..."
          sleep 2

          echo "Wiring output ports to hardware devices..."
          "$ETC_DIR/../surround-51-wire"

      - name: surround-51-wire
        content: |
          #!/bin/bash
          set -euo pipefail

          # Wait for the surround_51_output node to appear
          for i in $(seq 1 30); do
            if pw-link -o 2>/dev/null | grep -q "surround_51_output:"; then
              break
            fi
            sleep 0.5
          done

          if ! pw-link -o 2>/dev/null | grep -q "surround_51_output:"; then
            echo "Error: surround_51_output node not found after waiting"
            exit 1
          fi

          # Hardware device node names
          MPOW="alsa_output.usb-QTIL_LP-UNF_ABCDEF0123456789-00.analog-stereo"
          FIIO="alsa_output.usb-WEIL_WEILIANG_24BIT_USB-01.analog-stereo"
          XFI="alsa_output.usb-Creative_Technology_Ltd_SB_X-Fi_Surround_5.1_Pro_00000658-00.analog-stereo"

          SRC="surround_51_output"

          # Disconnect any existing links from our output first
          pw-link -o -I 2>/dev/null | grep "^    ${SRC}:" | while read -r peer port; do
            pw-link -d "${port}" "${peer}${port}" 2>/dev/null || true
          done

          # Disconnect auto-linked hardware inputs to prevent duplex routing
          for dev in "$MPOW" "$FIIO" "$XFI"; do
            pw-link -d "${SRC}:output_FL" "${dev}:playback_FL" 2>/dev/null || true
            pw-link -d "${SRC}:output_FR" "${dev}:playback_FR" 2>/dev/null || true
            pw-link -d "${SRC}:output_FC" "${dev}:playback_FL" 2>/dev/null || true
            pw-link -d "${SRC}:output_LFE" "${dev}:playback_FL" 2>/dev/null || true
            pw-link -d "${SRC}:output_RL" "${dev}:playback_FL" 2>/dev/null || true
            pw-link -d "${SRC}:output_RR" "${dev}:playback_FL" 2>/dev/null || true
          done

          # Routing:
          #   mix_front_L (FL+0.4*FC) -> Mpow R (front left speaker)
          #   mix_front_R (FR+0.4*FC) -> FiiO L (front right speaker)
          #   RL                       -> Mpow L (rear left speaker)
          #   RR                       -> FiiO R (rear right speaker)
          #   LFE/sub output           -> SB X-Fi L+R (subwoofer)

          # Mpow HC5: L = Rear Left, R = Front Left
          pw-link "${SRC}:output_FL" "${MPOW}:playback_FR"
          pw-link "${SRC}:output_RL" "${MPOW}:playback_FL"

          # FiiO E10: L = Front Right, R = Rear Right
          pw-link "${SRC}:output_FR" "${FIIO}:playback_FL"
          pw-link "${SRC}:output_RR" "${FIIO}:playback_FR"

          # SB X-Fi: both channels get LFE (mono subwoofer)
          pw-link "${SRC}:output_LFE" "${XFI}:playback_FL"
          pw-link "${SRC}:output_LFE" "${XFI}:playback_FR"

          echo "Surround 5.1 wiring complete."
          echo ""
          echo "Routing:"
          echo "  FL+0.4*FC -> Mpow R  (front left speaker)"
          echo "  FR+0.4*FC -> FiiO L  (front right speaker)"
          echo "  RL        -> Mpow L  (rear left speaker)"
          echo "  RR        -> FiiO R  (rear right speaker)"
          echo "  LFE       -> SB X-Fi (subwoofer)"

    ENV:
      ETC: "{{ETC}}"
      APP: pipewire
  tasks:
    - import_tasks: tasks/compfuzor.includes
