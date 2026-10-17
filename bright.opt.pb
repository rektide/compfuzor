---
- hosts: all
  vars:
    TYPE: bright
    INSTANCE: main
    USERMODE: true
    PKGS:
      - ddcutil
    # The target monitor. BRIGHT_TARGET substring-matches detected model
    # names (case-insensitive; exactly one match, ambiguity is an error).
    # On first use the function resolves it to a device, caching the bus
    # into exported BRIGHT_DEV (below) so later calls skip the detect probe.
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
          bright(): DDC/CI brightness via ddcutil. BRIGHT_TARGET
          substring-matches one detected model (ambiguity fails); the
          resolved bus caches into exported BRIGHT_DEV on first use so
          later calls skip probing. Migrated from ~/.zshrc bright()
          (ddccontrol -r 0x10 dev:/dev/i2c-8). No args reads the level;
          args write (95, or ddcutil +/- suffixes).
        functions:
          bright: |
            emulate -L zsh
            setopt extendedglob
            local -a sel
            if [[ -n "$BRIGHT_DEV" ]]; then
              sel=(--bus "${BRIGHT_DEV##*/i2c-}")
            else
              [[ -n "$BRIGHT_TARGET" ]] || { print -u2 "bright: BRIGHT_TARGET is empty"; return 1 }
              local out line dev i
              local -a lines devs models hits picked parts
              out=$(ddcutil detect --terse 2>/dev/null) || { print -u2 "bright: ddcutil detect failed"; return 1 }
              lines=("${(f)out}")
              for line in "$lines[@]"; do
                case "$line" in
                  *"I2C bus:"*) dev="${line##*bus:[[:space:]]##}" ;;
                  *"Monitor:"*)
                    [[ -n "$dev" ]] || continue
                    parts=("${(@s.:.)${line##*Monitor:[[:space:]]##}}")
                    devs+=("$dev")
                    models+=("${parts[2]}")
                    dev=""
                    ;;
                esac
              done
              for i in {1..${#models}}; do
                if [[ ${(L)models[$i]} = *"${(L)BRIGHT_TARGET}"* ]]; then
                  hits+=("$i")
                  picked+=("${models[$i]}")
                fi
              done
              case "${#hits}" in
                0)
                  print -u2 "bright: no detected model matches BRIGHT_TARGET='$BRIGHT_TARGET' (detected: ${(j:, :)models})"
                  return 1
                  ;;
                1)
                  BRIGHT_DEV="${devs[$hits[1]]}"
                  export BRIGHT_DEV
                  print -u2 "bright: cached BRIGHT_DEV=$BRIGHT_DEV for this shell (pin it to skip probing; unset to re-match)"
                  ;;
                *)
                  print -u2 "bright: BRIGHT_TARGET='$BRIGHT_TARGET' matches multiple models: ${(j:, :)picked}; make it more specific"
                  return 1
                  ;;
              esac
              sel=(--bus "${BRIGHT_DEV##*/i2c-}")
            fi
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

          {{BINS_DIR}}/install-zim-user.sh

      The importer feeds this contributor into the effective host context
      (ZIM_HOST_DIR, else the ~/.config/zsh/zimfw.conf registry, else
      /opt/zim-main) and rebuilds it. New shells then define `bright()`;
      verify with `whence -v bright`.

      ## Usage

          bright          # read brightness (getvcp)
          bright 95       # set brightness (setvcp; also accepts +/- suffixes)

      ## Knobs

      - BRIGHT_TARGET: substring matched (case-insensitive) against the
        model names `ddcutil detect` reports. Exactly one match must
        survive; zero matches errors with the detected models, and
        ambiguity errors listing the contenders. Default {{BRIGHT_MODEL}}
        (the Acer XV275K P3).
      - BRIGHT_DEV: NOT set by this deployment. On first use, `bright`
        resolves BRIGHT_TARGET and caches the winning device here
        (exported, /dev/i2c-N) for the rest of the shell session, so only
        the first call pays the ~2s detect probe; later calls address the
        bus directly (`ddcutil --bus`). Pin it in ~/.zshenv to skip the
        probe in every new shell — path (/dev/i2c-8) and bare bus number
        (8) both work. `unset BRIGHT_DEV` re-matches, and clearing it is
        the recovery when a replug renumbers buses: a stale pin fails
        fast at ddcutil instead of silently probing.
      - BRIGHT_VCP: VCP feature code, default 10 (brightness). 12 is contrast,
        62 audio loudness, D6 power mode.
      - BRIGHT_TARGET and BRIGHT_VCP ride through ZIM_ENV into interactive
        shells; the function also carries matching literal fallbacks, and
        each var's don't-stomp guard preserves a non-empty shell value
        unless COMPFUZOR_ENV_OVERWRITE includes it.

      ## Migration

      Replaces the ~/.zshrc function `ddccontrol -r 0x10 dev:/dev/i2c-8 -w $*`.
      ddcutil replaces ddccontrol (probing, VCP naming, active maintenance);
      the same VCP code 0x10 on the same monitor is written either way. One
      behavior change: bare `bright` now reads the current level instead of
      invoking a write with no value. The old function's hardcoded bus lives
      on as an opt-in: pin BRIGHT_DEV=/dev/i2c-8 to skip probing entirely.

      ## Caveats

      The second monitor (InnoView) does not implement DDC/CI at all; it is
      unreachable by design. DDC/CI is slow (~1 command/second with dynamic
      sleeps) and only responds while the monitor is awake. /dev/i2c-* access
      must reach the invoking user (i2c-dev group membership or udev rule).

      References: [ddcutil](https://www.ddcutil.com/),
      [MCCS VCP codes](https://www.ddcutil.com/vcpinfo).
  tasks:
    - import_tasks: tasks/compfuzor.includes
