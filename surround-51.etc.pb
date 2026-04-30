---
- hosts: all
  vars:
    TYPE: surround-51
    INSTANCE: main
    BINS:
      - name: surround-51-gen.js
        content: |
          #!/usr/bin/env node
          const args = process.argv.slice(2);
          const opts = {
            frontMix: 0.7,
            centerMix: 0.4,
            highpass: 0,
            subLFE: 1.0,
            subMain: 0.0,
            subCenter: 0.0,
          };

          function usage() {
            console.error(`Usage: surround-51-gen [options]

Options:
  --front-mix <gain>   Front channel gain to virtual front speakers (default: ${opts.frontMix})
  --center-mix <gain>  Center channel gain to virtual front speakers (default: ${opts.centerMix})
  --highpass <hz>      Highpass frequency for front+rear speakers, 0=off (default: ${opts.highpass})
  --sub-lfe <gain>     LFE channel gain to subwoofer (default: ${opts.subLFE})
  --sub-main <gain>    Main (FL+FR) gain to subwoofer (default: ${opts.subMain})
  --sub-center <gain>  Center channel gain to subwoofer (default: ${opts.subCenter})

Hardware routing (hardcoded):
  Mpow HC5 L=rear-left  R=front-left   (FL + centerMix*FC)
  FiiO E10 L=front-right R=rear-right  (FR + centerMix*FC)
  SB X-Fi = subwoofer                 (subLFE*LFE + subMain*(FL+FR) + subCenter*FC)

Example:
  surround-51-gen --highpass 80 --sub-main 0.5 > ~/.config/pipewire/pipewire.conf.d/surround-51.conf
`);
          }

          for (let i = 0; i < args.length; i++) {
            switch (args[i]) {
              case "--front-mix": opts.frontMix = parseFloat(args[++i]); break;
              case "--center-mix": opts.centerMix = parseFloat(args[++i]); break;
              case "--highpass": opts.highpass = parseFloat(args[++i]); break;
              case "--sub-lfe": opts.subLFE = parseFloat(args[++i]); break;
              case "--sub-main": opts.subMain = parseFloat(args[++i]); break;
              case "--sub-center": opts.subCenter = parseFloat(args[++i]); break;
              case "-h": case "--help": usage(); process.exit(0);
              default: console.error(`Unknown option: ${args[i]}`); usage(); process.exit(1);
            }
          }

          const hp = opts.highpass > 0;

          const nodes = [
            { name: "copy_FL", type: "builtin", label: "copy" },
            { name: "copy_FR", type: "builtin", label: "copy" },
            { name: "copy_FC", type: "builtin", label: "copy" },
            { name: "copy_LFE", type: "builtin", label: "copy" },
            { name: "copy_RL", type: "builtin", label: "copy" },
            { name: "copy_RR", type: "builtin", label: "copy" },
            { name: "copy_FC2", type: "builtin", label: "copy" },
            {
              name: "mix_front_L", type: "builtin", label: "mixer",
              control: { "Gain 1": opts.frontMix, "Gain 2": opts.centerMix },
            },
            {
              name: "mix_front_R", type: "builtin", label: "mixer",
              control: { "Gain 1": opts.frontMix, "Gain 2": opts.centerMix },
            },
            {
              name: "mix_sub", type: "builtin", label: "mixer",
              control: {
                "Gain 1": opts.subMain,
                "Gain 2": opts.subMain,
                "Gain 3": opts.subCenter,
                "Gain 4": opts.subLFE,
              },
            },
          ];

          if (hp) {
            for (const id of ["front_L", "front_R", "rear_L", "rear_R"]) {
              nodes.push({
                name: `hp_${id}`, type: "builtin", label: "bq_highpass",
                control: { Freq: opts.highpass, Q: 0.707 },
              });
            }
          }

          const links = [
            { output: "copy_FL:Out", input: "mix_front_L:In 1" },
            { output: "copy_FC:Out", input: "mix_front_L:In 2" },
            { output: "copy_FR:Out", input: "mix_front_R:In 1" },
            { output: "copy_FC2:Out", input: "mix_front_R:In 2" },
            { output: "copy_FL:Out", input: "mix_sub:In 1" },
            { output: "copy_FR:Out", input: "mix_sub:In 2" },
            { output: "copy_FC:Out", input: "mix_sub:In 3" },
            { output: "copy_LFE:Out", input: "mix_sub:In 4" },
          ];

          if (hp) {
            links.push(
              { output: "mix_front_L:Out", input: "hp_front_L:In" },
              { output: "mix_front_R:Out", input: "hp_front_R:In" },
              { output: "copy_RL:Out", input: "hp_rear_L:In" },
              { output: "copy_RR:Out", input: "hp_rear_R:In" },
            );
          }

          const outputs = hp
            ? ["hp_front_L:Out", "hp_front_R:Out", "copy_FC:Out", "mix_sub:Out", "hp_rear_L:Out", "hp_rear_R:Out"]
            : ["mix_front_L:Out", "mix_front_R:Out", "copy_FC:Out", "mix_sub:Out", "copy_RL:Out", "copy_RR:Out"];

          const desc = `5.1 Surround (front=${opts.frontMix} center=${opts.centerMix}${hp ? ` hp=${opts.highpass}` : ""} sub=lfe:${opts.subLFE},main:${opts.subMain},ctr:${opts.subCenter})`;

          const config = {
            "context.modules": [{
              name: "libpipewire-module-filter-chain",
              args: {
                "node.description": desc,
                "media.name": "surround_51",
                "filter.graph": {
                  nodes,
                  links,
                  inputs: [
                    "copy_FL:In", "copy_FR:In", "copy_FC:In",
                    "copy_LFE:In", "copy_RL:In", "copy_RR:In",
                  ],
                  outputs,
                },
                "capture.props": {
                  "node.name": "surround_51_input",
                  "media.class": "Audio/Sink",
                  "audio.channels": 6,
                  "audio.position": ["FL", "FR", "FC", "LFE", "RL", "RR"],
                },
                "playback.props": {
                  "node.name": "surround_51_output",
                  "audio.channels": 6,
                  "audio.position": ["FL", "FR", "FC", "LFE", "RL", "RR"],
                  "stream.dont-remix": true,
                  "node.passive": true,
                },
              },
            }],
          };

          console.log(JSON.stringify(config, null, 2));

      - name: surround-51-activate
        content: |
          #!/bin/bash
          set -euo pipefail

          CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/pipewire.conf.d"
          BIN_DIR="$(cd "$(dirname "$0")" && pwd)"

          if [ "$#" -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
            echo "Usage: $(basename "$0") [GEN_OPTIONS...] [--install] [--off]"
            echo ""
            echo "Generates and optionally installs a surround 5.1 pipewire filter-chain config."
            echo "Passes all options through to surround-51-gen, plus:"
            echo "  --install    Write config and restart pipewire + wire"
            echo "  --off        Remove config and restart pipewire"
            echo ""
            echo "Generator options:"
            "$BIN_DIR/surround-51-gen.js" --help
            exit 0
          fi

          INSTALL=false
          OFF=false
          GEN_ARGS=()

          for arg in "$@"; do
            case "$arg" in
              --install) INSTALL=true ;;
              --off) OFF=true ;;
              --front-mix|--center-mix|--highpass|--sub-lfe|--sub-main|--sub-center)
                GEN_ARGS+=("$arg")
                shift || true
                GEN_ARGS+=("$1")
                ;;
              *) GEN_ARGS+=("$arg") ;;
            esac
          done

          if $OFF; then
            rm -f "$CONF_DIR/surround-51.conf"
            echo "Surround 5.1 disabled. Restarting PipeWire..."
            systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
            exit 0
          fi

          mkdir -p "$CONF_DIR"
          echo "Generating surround 5.1 config..."
          "$BIN_DIR/surround-51-gen.js" "${GEN_ARGS[@]}" > "$CONF_DIR/surround-51.conf"

          if $INSTALL; then
            echo "Restarting PipeWire..."
            systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
            echo "Waiting for PipeWire to stabilize..."
            sleep 2
            echo "Wiring output ports to hardware..."
            "$BIN_DIR/surround-51-wire"
          else
            echo "Config written to $CONF_DIR/surround-51.conf"
            echo "Run with --install to restart pipewire and wire ports."
          fi

      - name: surround-51-wire
        content: |
          #!/bin/bash
          set -euo pipefail

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

          MPOW="alsa_output.usb-QTIL_LP-UNF_ABCDEF0123456789-00.analog-stereo"
          FIIO="alsa_output.usb-WEIL_WEILIANG_24BIT_USB-01.analog-stereo"
          XFI="alsa_output.usb-Creative_Technology_Ltd_SB_X-Fi_Surround_5.1_Pro_00000658-00.analog-stereo"
          SRC="surround_51_output"

          # Disconnect auto-links
          for dev in "$MPOW" "$FIIO" "$XFI"; do
            for ch in FL FR FC LFE RL RR; do
              pw-link -d "${SRC}:output_${ch}" "${dev}:playback_FL" 2>/dev/null || true
              pw-link -d "${SRC}:output_${ch}" "${dev}:playback_FR" 2>/dev/null || true
            done
          done

          # Mpow HC5: L=rear-left, R=front-left
          pw-link "${SRC}:output_FL" "${MPOW}:playback_FR"
          pw-link "${SRC}:output_RL" "${MPOW}:playback_FL"

          # FiiO E10: L=front-right, R=rear-right
          pw-link "${SRC}:output_FR" "${FIIO}:playback_FL"
          pw-link "${SRC}:output_RR" "${FIIO}:playback_FR"

          # SB X-Fi: subwoofer on both channels
          pw-link "${SRC}:output_LFE" "${XFI}:playback_FL"
          pw-link "${SRC}:output_LFE" "${XFI}:playback_FR"

          echo "Surround 5.1 wiring complete."
          echo "  FL+center -> Mpow R  (front left speaker)"
          echo "  FR+center -> FiiO L  (front right speaker)"
          echo "  RL        -> Mpow L  (rear left speaker)"
          echo "  RR        -> FiiO R  (rear right speaker)"
          echo "  sub mix   -> SB X-Fi (subwoofer)"

    ENV:
      ETC: "{{ETC}}"
      APP: pipewire
  tasks:
    - import_tasks: tasks/compfuzor.includes
