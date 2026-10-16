---
- hosts: all
  vars:
    TYPE: bright
    INSTANCE: main
    USERMODE: true
    PKGS:
      - ddcutil
    # The target monitor, matched by ddcutil --model (EDID model name).
    # Model matching survives bus renumbering, unlike the raw /dev/i2c-N the
    # old ~/.zshrc bright() hardcoded; BRIGHT_TARGET is the exported knob.
    BRIGHT_MODEL: XV275K P3
    # VCP feature code: 0x10 brightness (range 0-100). Other useful codes:
    # 0x12 contrast, 0x62 audio volume, 0xD6 power mode.
    BRIGHT_VCP: '10'
    ENV:
      BRIGHT_TARGET: "{{BRIGHT_MODEL}}"
      BRIGHT_VCP: "{{BRIGHT_VCP}}"
    # Promote the knobs into an interactive-shell Zim env module. Phase 54
    # (opencode/watchwoman precedent) loads it just ahead of the tools band.
    ZIM_ENV: [BRIGHT_TARGET, BRIGHT_VCP]
    ZIM_ENV_PHASE: 54
    ZIM_MODULES:
      - name: bright
        phase: tools
        comment: >-
          bright(): DDC/CI brightness via ddcutil for the Acer XV275K P3.
          Migrated from ~/.zshrc bright() (ddccontrol -r 0x10 dev:/dev/i2c-8).
          No args reads the level; args write (95, or ddcutil +/- suffixes).
        functions:
          bright: |
            emulate -L zsh
            local -a sel
            sel=(-l "${BRIGHT_TARGET:-XV275K P3}")
            if (( $# == 0 )); then
              ddcutil $sel getvcp "${BRIGHT_VCP:-10}"
            else
              ddcutil $sel setvcp "${BRIGHT_VCP:-10}" "$@"
            fi
    README: |
      # bright: DDC/CI brightness for the Acer over ddcutil

      Deploys a `bright()` Zsh function and its knobs as a Zim contributor.
      Rendering is inert for your shell: it lands fragments and an importer
      under {{DIR}}, installs nothing into Zim, and changes no monitor state.
      Importing is the explicit shell-configuration action:

          {{BINS_DIR}}/install-zimfw.sh

      The importer feeds this contributor into the effective host context
      (ZIM_HOST_DIR, else the ~/.config/zsh/zimfw.conf registry, else
      /opt/zim-main) and rebuilds it. New shells then define `bright()`;
      verify with `whence -v bright`.

      ## Usage

          bright          # read brightness (getvcp)
          bright 95       # set brightness (setvcp; also accepts +/- suffixes)

      ## Knobs

      - BRIGHT_TARGET: ddcutil --model selector. Defaults to BRIGHT_MODEL
        ({{BRIGHT_MODEL}}, the Acer XV275K P3). Model matching survives USB /
        cable / bus renumbering, unlike the hardcoded /dev/i2c-8 bus this
        replaces. Run `ddcutil detect` to see candidate model names.
      - BRIGHT_VCP: VCP feature code, default 10 (brightness). 12 is contrast,
        62 audio loudness, D6 power mode.
      - Both ride through ZIM_ENV into interactive shells; the function also
        carries matching literal fallbacks, and each var's don't-stomp guard
        preserves a non-empty shell value unless COMPFUZOR_ENV_OVERWRITE
        includes it.

      ## Migration

      Replaces the ~/.zshrc function `ddccontrol -r 0x10 dev:/dev/i2c-8 -w $*`.
      ddcutil replaces ddccontrol (probing, VCP naming, active maintenance);
      the same VCP code 0x10 on the same monitor is written either way. One
      behavior change: bare `bright` now reads the current level instead of
      invoking a write with no value.

      ## Caveats

      The second monitor (InnoView) does not implement DDC/CI at all; it is
      unreachable by design. DDC/CI is slow (~1 command/second with dynamic
      sleeps) and only responds while the monitor is awake. /dev/i2c-* access
      must reach the invoking user (i2c-dev group membership or udev rule).

      References: [ddcutil](https://www.ddcutil.com/),
      [MCCS VCP codes](https://www.ddcutil.com/vcpinfo).
  tasks:
    - import_tasks: tasks/compfuzor.includes
