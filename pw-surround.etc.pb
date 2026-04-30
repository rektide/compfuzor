---
# pw-surround — PipeWire virtual 5.1 surround sound via filter-chain
#
# Creates a 6-channel virtual sink (FL FR FC LFE RL RR) with configurable
# channel mixing and optional highpass. Three scripts handle the lifecycle:
#
#   surround-51-gen.js   Generate filter-chain JSON config (parameterized)
#   surround-51-activate Generate + install + restart + wire
#   surround-51-wire     Route virtual sink ports to physical hardware via pw-link
#
# Hardware layout:
#   Mpow HC5 (LP-UNF USB) L=rear-left  R=front-left
#   FiiO E10 (WEILIANG)   L=front-right R=rear-right
#   SB X-Fi Surround 5.1  both channels = subwoofer (has its own crossover)
#
# The filter-chain mixing matrix:
#   Front speakers:  frontMix*FL/FR + centerMix*FC
#   Subwoofer:       subLFE*LFE + subMain*(FL+FR) + subCenter*FC
#   Rear speakers:   direct passthrough (with optional highpass)
#
- hosts: all
  vars:
    TYPE: pw-surround
    INSTANCE: main

    # Mixing defaults — exported to env.export and available at runtime.
    # The surround-51-gen.js script reads these as PW_SURROUND_* env vars.
    # CLI args override env vars, env vars override these defaults.
    PW_SURROUND_FRONT_MIX: "0.7"
    PW_SURROUND_CENTER_MIX: "0.4"
    PW_SURROUND_HIGHPASS: "0"
    PW_SURROUND_SUB_LFE: "1.0"
    PW_SURROUND_SUB_MAIN: "0.0"
    PW_SURROUND_SUB_CENTER: "0.0"

    # PipeWire device node names for the hardware routing script.
    # These are Jinja-rendered into surround-51-wire at build time.
    PW_SURROUND_DEVICE_MPOW: "alsa_output.usb-QTIL_LP-UNF_ABCDEF0123456789-00.analog-stereo"
    PW_SURROUND_DEVICE_FIIO: "alsa_output.usb-WEIL_WEILIANG_24BIT_USB-01.analog-stereo"
    PW_SURROUND_DEVICE_XFI: "alsa_output.usb-Creative_Technology_Ltd_SB_X-Fi_Surround_5.1_Pro_00000658-00.analog-stereo"

    BINS:
      # Config generator — produces pipewire filter-chain JSON to stdout.
      # Reads PW_SURROUND_* env vars at runtime for all mixing parameters.
      # CLI args override env vars, env vars override compiled-in defaults.
      # Raw copy: no Jinja templating needed for this file.
      - name: surround-51-gen.js
        src: surround-51-gen.js
        raw: true

      # Activation wrapper — generates config, installs to pipewire.conf.d,
      # restarts pipewire, and runs the wire script. Pass --install to do the
      # full activate, or just generate config without installing.
      - name: surround-51-activate
        src: surround-51-activate
        no_header: true

      # Port wiring — uses pw-link to disconnect auto-links and route each
      # virtual sink output channel to the correct physical device channel.
      # Device names are Jinja-rendered from PW_SURROUND_DEVICE_* vars above.
      - name: surround-51-wire
        src: surround-51-wire
        no_header: true

    ENV:
      ETC: "{{ETC}}"
      APP: pipewire
  tasks:
    - import_tasks: tasks/compfuzor.includes
