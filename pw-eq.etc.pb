---
# pw-eq — shared parametric EQ toolkit for PipeWire filter-chain scenarios
#
# Common machinery for the two switchable EQ arrangements; scenario
# selection lives in the sibling playbooks, each backed by a systemd
# user service (pw-loopback.srv.pb tradition):
#
#   pw-eq-fiio.etc.pb   (preferred) combine -> eq_sink -> EQ -> FiiO E10
#                       systemctl --user start pw-eq-fiio
#   pw-eq-global.etc.pb            eq_global (default sink) -> EQ -> combine
#                       systemctl --user start pw-eq-global
#
# The scenario node names are load-bearing: combine_sink's fan-out
# whitelist admits eq_sink by name (see pipewire-virtual-sink.etc.pb);
# eq_global deliberately does not match, so the global chain never feeds
# its own output back into itself. One combine config serves both.
#
#   pw-eq-gen.js      Generate filter-chain JSON config (parameterized)
#   pw-eq-activate    Generate + install + restart + route; idempotent
#                     when the scenario is already asserted (session-start
#                     safe); scenario wrappers set PW_EQ_NODE/TARGET/
#                     DEFAULT_SINK/CONF/RM_CONF and exec this.
#
# Both scenarios share one curve spec, PW_EQ_BANDS below. The FiiO
# branch keeps its raw sibling fan stream (zero it manually in
# pavucontrol to avoid double playback); the global arrangement wants
# it back at 100%.
#
# This toolkit replaces EasyEffects in the live path after the
# 2026-10-18 session, where EE on this graph showed four failure modes:
# combine_sink fanning into its virtual sink (feedback),
# process-all-outputs stream-moving destroying module-combine-stream
# fan streams, zombie disconnection across PipeWire restarts, and an
# intermittently self-unwiring player stream. A graph-native
# filter-chain has no GUI process and survives restarts by construction.
# EE remains installed for occasional GUI experiments; if it runs:
# process-all-outputs must stay OFF (it kills the combine fan streams)
# and it must be restarted after any PipeWire restart.
#
# Band spec: freqHz:gaindB:Q:type — highshelf, lowshelf, peaking,
# highpass, lowpass, bandpass, notch, allpass (pw-eq-gen.js --help).

- hosts: all
  vars:
    BINS:
      # Config generator — produces pipewire filter-chain JSON to stdout.
      # Reads PW_EQ_* env vars at runtime; CLI args override env vars.
      # Raw copy: no Jinja templating for this file.
      - name: pw-eq-gen.js
        src: pw-eq-gen.js
        raw: true

      # Activation core — generates config, installs to pipewire.conf.d
      # (PW_EQ_CONF names it), removes PW_EQ_RM_CONF, restarts pipewire,
      # sets the default sink per PW_EQ_DEFAULT_SINK policy, and
      # restarts pw-loopback so line-in retargets. --off removes.
      # Scenario wrappers (pw-eq-fiio / pw-eq-global) exec this.
      - name: pw-eq-activate
        src: pw-eq-activate
        helpers: false

    ENV:
      APP: pipewire

      # Shared defaults — scenario wrappers override everything except
      # the curve. Direct pw-eq-activate use runs the GLOBAL arrangement
      # with these (node eq_sink is NOT in the fan-out whitelist unless
      # targeted at a hardware sink... use the scenario wrappers).
      PW_EQ_BANDS: "3500:-3:0.7:highshelf,11000:-4:0.7:highshelf"
      PW_EQ_NODE: "eq_sink"
      PW_EQ_TARGET: "combine_sink"
      PW_EQ_DEFAULT_SINK: ""
      PW_EQ_CONF: "pw-eq.conf"
      PW_EQ_RM_CONF: ""
  tasks:
    - import_tasks: tasks/compfuzor.includes
