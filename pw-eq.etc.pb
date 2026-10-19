---
# pw-eq — FiiO-branch parametric EQ via PipeWire filter-chain
#
# Creates a stereo virtual sink (eq_sink) whose audio passes through a
# biquad band chain (default: treble roll-off — high shelf 3.5 kHz −3 dB,
# high shelf 11 kHz −4 dB) before delivery to the FiiO E10 (WEILIANG)
# hardware sink.
#
# Topology (branch EQ, chosen 2026-10-18 after the global variant):
#   apps + line-in -> combine_sink (default) -> fan-out:
#     -> 4 hardware sinks raw
#     -> WEILIANG raw fan stream          (zero this manually in pavucontrol)
#     -> eq_sink -> EQ bands -> WEILIANG  (the EQ'd Fiiio feed)
#   eq_sink is deliberately included in combine_sink's fan-out whitelist;
#   see pipewire-virtual-sink.etc.pb. The raw WEILIANG fan stream is NOT
#   excluded by rule because negated exclusions in stream.rules tore down
#   all fan streams on this stack (2026-10-18); the double feed on the
#   FiiO is instead silenced by zeroing the "Combine Sink output" stream
#   on the WEILIANG sink in pavucontrol's Playback tab. If that zeroes
#   other fan streams too after a restart (they share a media name for
#   stream-restore), revisit with a per-node exclusion.
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
      # restarts pipewire, sets the default sink (combine_sink when the EQ
      # targets a hardware sink; the eq sink itself when it targets
      # combine_sink), and restarts pw-loopback so line-in retargets.
      # --off removes.
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

      # Filter-chain sink node and delivery target. TARGET is the FiiO E10
      # (WEILIANG) hardware sink; combine_sink fans into eq_sink and the
      # EQ'd output lands only on the FiiO. Point TARGET back at
      # combine_sink to restore the global-EQ arrangement.
      PW_EQ_NODE: "eq_sink"
      PW_EQ_TARGET: "alsa_output.usb-WEIL_WEILIANG_24BIT_USB-01.analog-stereo"

      # Default sink while the branch EQ is active. Leave empty for the
      # activate script's policy (combine_sink for branch EQ, eq_sink for
      # global EQ).
      PW_EQ_DEFAULT_SINK: ""
  tasks:
    - import_tasks: tasks/compfuzor.includes
