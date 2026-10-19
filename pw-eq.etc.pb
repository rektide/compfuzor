---
# pw-eq — system-wide parametric EQ sink via PipeWire filter-chain
#
# Creates a stereo virtual sink (eq_sink) whose audio passes through a
# biquad band chain (default: treble roll-off — high shelf 3.5 kHz −3 dB,
# high shelf 11 kHz −4 dB) before delivery to a target sink (default:
# combine_sink, which fans out to all ALSA hardware sinks).
#
# This is the codified EQ baseline. It replaces EasyEffects in the live
# path after the 2026-10-18 session, where EE on this graph showed four
# failure modes: combine_sink fanning into its virtual sink (feedback),
# process-all-outputs stream-moving destroying module-combine-stream fan
# streams, zombie disconnection across PipeWire restarts, and an
# intermittently self-unwiring player stream. A graph-native filter-chain
# has no GUI process, survives restarts by construction, and catches the
# permanent line-in loopback (pw-loopback follows the default sink).
#
# EasyEffects remains installed for occasional GUI experiments. If it runs:
# process-all-outputs must stay OFF (it kills the combine fan streams) and
# it must be restarted after any PipeWire restart (it never reconnects).
#
#   pw-eq-gen.js      Generate filter-chain JSON config (parameterized)
#   pw-eq-activate    Generate + install + restart + route default sink
#
# The line-in path this serves:
#   alsa_input.pci-0000_0b_00.4 -> pw-loopback -> eq_sink -> EQ bands
#   -> combine_sink -> all alsa_output.* hardware sinks
#
# Tuning the curve: edit PW_EQ_BANDS below (freqHz:gaindB:Q:type), rerun
#   `pw-eq-activate --install`, or pass --bands directly. Type suffixes:
#   highshelf, lowshelf, peaking, highpass, lowpass, bandpass, notch, allpass.

- hosts: all
  vars:
    BINS:
      # Config generator — produces pipewire filter-chain JSON to stdout.
      # Reads PW_EQ_* env vars at runtime; CLI args override env vars.
      # Raw copy: no Jinja templating for this file.
      - name: pw-eq-gen.js
        src: pw-eq-gen.js
        raw: true

      # Activation wrapper — generates config, installs to pipewire.conf.d,
      # restarts pipewire, points the default sink at eq_sink, and restarts
      # pw-loopback so line-in retargets through the EQ. --off removes.
      - name: pw-eq-activate
        src: pw-eq-activate
        helpers: false

    ENV:
      APP: pipewire

      # EQ curve — exported to env.export and available at runtime.
      # Band spec: freqHz:gaindB:Q:type, comma-separated.
      # Default: the treble roll-off requested 2026-10-18 — gentle shelf
      # from 3.5 kHz plus a steeper one above 11 kHz.
      PW_EQ_BANDS: "3500:-3:0.7:highshelf,11000:-4:0.7:highshelf"

      # Filter-chain sink and delivery target. TARGET stays combine_sink
      # (the fan-out); changing TARGET re-points delivery only.
      PW_EQ_NODE: "eq_sink"
      PW_EQ_TARGET: "combine_sink"
  tasks:
    - import_tasks: tasks/compfuzor.includes
