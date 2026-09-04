#!/usr/bin/env python3
"""Exercise the reversible, session-local emergency shell mode."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
ZIM_MODULE = ROOT / "files/zim/emergency.zsh"
ATUIN_MODULE = ROOT / "files/atuin/emergency.zsh"


def test_emergency_shell_mode() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-emergency-") as temporary:
        directory = Path(temporary)
        systemctl_log = directory / "systemctl.log"
        systemctl = directory / "systemctl"
        systemctl.write_text(
            """#!/bin/sh
printf '%s\\n' "$*" >> "$SYSTEMCTL_LOG"
if [ "$2" = start ] && [ -n "$SYSTEMCTL_FAIL_START_ONCE" ] \\
  && [ ! -e "$SYSTEMCTL_FAIL_MARKER" ]; then
  : > "$SYSTEMCTL_FAIL_MARKER"
  exit 1
fi
""",
            encoding="utf-8",
        )
        systemctl.chmod(0o755)

        env = os.environ.copy()
        env.update(
            {
                "ATUIN_EMERGENCY_SYSTEMCTL": str(systemctl),
                "ATUIN_MODULE": str(ATUIN_MODULE),
                "SYSTEMCTL_LOG": str(systemctl_log),
                "SYSTEMCTL_FAIL_MARKER": str(directory / "failed-start"),
                "ZIM_MODULE": str(ZIM_MODULE),
            }
        )
        env.pop("COMPFUZOR_EMERGENCY", None)

        script = r"""
setopt errexit

keep_precmd() { :; }
keep_preexec() { :; }
keep_chpwd() { :; }
keep_periodic() { :; }
keep_history() { :; }
keep_exit() { :; }
_atuin_precmd() { :; }
_atuin_preexec() { :; }
_atuin_zshaddhistory() { :; }

precmd_functions=(_atuin_precmd keep_precmd)
preexec_functions=(_atuin_preexec keep_preexec)
chpwd_functions=(keep_chpwd)
periodic_functions=(keep_periodic)
zshaddhistory_functions=(_atuin_zshaddhistory keep_history)
zshexit_functions=(keep_exit)
ZSH_AUTOSUGGEST_STRATEGY=(atuin match_prev_cmd atuin)
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
_ZSH_AUTOSUGGEST_DISABLED=preserve
PROMPT='rich prompt '
RPROMPT='rich right'
PROMPT2='rich continue '
HISTFILE=/tmp/compfuzor-history
bindkey -v
bindkey '^R' clear-screen
bindkey -N compfuzor-test
bindkey -M compfuzor-test '^X' clear-screen
bindkey -A compfuzor-test alternate-test
setopt correct correctall hashlistall

typeset -ga probe_calls=()
_emergency_probe_on() { probe_calls+=(on); }
_emergency_probe_off() { probe_calls+=(off); }

setopt ksharrays
source "$ATUIN_MODULE"
source "$ATUIN_MODULE"
source "$ZIM_MODULE"
unsetopt ksharrays

[[ $(_emergency status) == $'emergency: off\n  atuin: off\n  probe: off\n  zim: off' ]]

setopt ksharrays
_emergency on
unsetopt ksharrays

[[ $COMPFUZOR_EMERGENCY == 1 ]]
[[ ${(t)COMPFUZOR_EMERGENCY} == *export* ]]
[[ $PROMPT == 'emergency:%~%# ' ]]
[[ -z $RPROMPT && $PROMPT2 == '> ' ]]
[[ -z ${HISTFILE+x} ]]
[[ $options[correct] == off && $options[correctall] == off ]]
[[ $options[hashlistall] == off ]]
(( ${#precmd_functions} == 0 ))
(( ${#preexec_functions} == 0 ))
(( ${#chpwd_functions} == 0 ))
(( ${#periodic_functions} == 0 ))
(( ${#zshaddhistory_functions} == 0 ))
(( ${#zshexit_functions} == 0 ))
(( ${#ZSH_HIGHLIGHT_HIGHLIGHTERS} == 0 ))
[[ ${(j:,:)ZSH_AUTOSUGGEST_STRATEGY} == match_prev_cmd ]]
[[ $(bindkey '^I') == *'_compfuzor_emergency_noop' ]]
[[ $(bindkey '^R') == *'history-incremental-search-backward' ]]
[[ $(_emergency status) == $'emergency: on\n  atuin: on\n  probe: on\n  zim: on' ]]

# repeated on is a state no-op: no actions re-run
_emergency on
[[ ${(j:,:)probe_calls} == on ]]

_emergency off

[[ -z ${COMPFUZOR_EMERGENCY+x} ]]
[[ $PROMPT == 'rich prompt ' && $RPROMPT == 'rich right' ]]
[[ $PROMPT2 == 'rich continue ' && $HISTFILE == /tmp/compfuzor-history ]]
[[ $options[correct] == on && $options[correctall] == on ]]
[[ $options[hashlistall] == on ]]
[[ ${(j:,:)precmd_functions} == _atuin_precmd,keep_precmd ]]
[[ ${(j:,:)preexec_functions} == _atuin_preexec,keep_preexec ]]
[[ ${(j:,:)chpwd_functions} == keep_chpwd ]]
[[ ${(j:,:)periodic_functions} == keep_periodic ]]
[[ ${(j:,:)zshaddhistory_functions} == _atuin_zshaddhistory,keep_history ]]
[[ ${(j:,:)zshexit_functions} == keep_exit ]]
[[ ${(j:,:)ZSH_HIGHLIGHT_HIGHLIGHTERS} == main,brackets ]]
[[ ${(j:,:)ZSH_AUTOSUGGEST_STRATEGY} == atuin,match_prev_cmd,atuin ]]
[[ $_ZSH_AUTOSUGGEST_DISABLED == preserve ]]
[[ $(bindkey '^R') == *'clear-screen' ]]
[[ $(bindkey -lL) == *'bindkey -A viins main'* ]]
[[ $(bindkey -M compfuzor-test '^X') == *'clear-screen' ]]
[[ $(bindkey -M alternate-test '^X') == *'clear-screen' ]]
[[ ${(j:,:)probe_calls} == on,off ]]
[[ $(_emergency status) == $'emergency: off\n  atuin: off\n  probe: off\n  zim: off' ]]

# per-subsystem control without engaging the whole-shell mode
_emergency atuin on
[[ -z ${COMPFUZOR_EMERGENCY+x} ]]
[[ $(_emergency atuin status) == 'atuin: on' ]]
[[ $(_emergency status) == $'emergency: off\n  atuin: on\n  probe: off\n  zim: off' ]]
_emergency atuin off
[[ $(_emergency atuin status) == 'atuin: off' ]]

# unknown subsystem is rejected with the available names
if _emergency bogus on; then
  print -u2 'unknown subsystem unexpectedly accepted'
  exit 1
fi

# global transitions only act on subsystems not already in the target state
_emergency atuin on
_emergency on
[[ ${(j:,:)probe_calls} == on,off,on ]]
_emergency off
[[ -z ${COMPFUZOR_EMERGENCY+x} ]]
[[ $PROMPT == 'rich prompt ' ]]
[[ ${(j:,:)probe_calls} == on,off,on,off ]]

# a failed off stays engaged per-subsystem and retries cleanly
export SYSTEMCTL_FAIL_START_ONCE=1
_emergency on
if _emergency off; then
  print -u2 'failed Atuin restart incorrectly reported success'
  exit 1
fi
[[ $COMPFUZOR_EMERGENCY == 1 ]]
[[ $PROMPT == 'emergency:%~%# ' ]]
[[ $(_emergency atuin status) == 'atuin: on' ]]
_emergency off
[[ -z ${COMPFUZOR_EMERGENCY+x} ]]
[[ $PROMPT == 'rich prompt ' ]]
[[ ${(j:,:)probe_calls} == on,off,on,off,on,off ]]

# cold shell: registry reload engages subsystem hooks, off restores + execs
typeset -a registered_hooks=("${(@s.:.)COMPFUZOR_EMERGENCY_HOOKS}")
(( ${registered_hooks[(Ie)$ATUIN_MODULE]} ))
(( ${#registered_hooks[@]} == 1 ))
unfunction _emergency_atuin_on _emergency_atuin_off
unset _COMPFUZOR_EMERGENCY_ATUIN_ACTIVE
unset _COMPFUZOR_EMERGENCY_STATE
unset _COMPFUZOR_EMERGENCY_HOOKS_LOADED
typeset -g _COMPFUZOR_EMERGENCY_COLD=1
typeset -gx COMPFUZOR_EMERGENCY=1
source "$ZIM_MODULE"
(( ${+functions[_emergency_atuin_on]} ))
[[ $PROMPT == 'emergency:%~%# ' ]]
typeset -g _COMPFUZOR_EMERGENCY_COLD=0
_emergency off
[[ -z ${COMPFUZOR_EMERGENCY+x} ]]
[[ $PROMPT == 'rich prompt ' ]]
[[ ${(j:,:)probe_calls} == on,off,on,off,on,off,on,off ]]

# subsystem toggle flips one entry without touching the others
_emergency probe toggle
[[ $(_emergency probe status) == 'probe: on' ]]
[[ ${(j:,:)probe_calls} == on,off,on,off,on,off,on,off,on ]]
_emergency probe toggle
[[ $(_emergency probe status) == 'probe: off' ]]
[[ ${(j:,:)probe_calls} == on,off,on,off,on,off,on,off,on,off ]]
"""

        result = subprocess.run(
            ["zsh", "-dfc", script],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise AssertionError(f"emergency shell test failed:\n{result.stdout}{result.stderr}")
        calls = systemctl_log.read_text(encoding="utf-8").splitlines()
        assert calls == [
            "--user stop --no-block atuin-daemon.service atuin-daemon.socket",
            "--user start --no-block atuin-daemon.socket",
            "--user stop --no-block atuin-daemon.service atuin-daemon.socket",
            "--user start --no-block atuin-daemon.socket",
            "--user stop --no-block atuin-daemon.service atuin-daemon.socket",
            "--user start --no-block atuin-daemon.socket",
            "--user stop --no-block atuin-daemon.service atuin-daemon.socket",
            "--user start --no-block atuin-daemon.socket",
            "--user start --no-block atuin-daemon.socket",
            "--user stop --no-block atuin-daemon.service atuin-daemon.socket",
            "--user start --no-block atuin-daemon.socket",
        ]


if __name__ == "__main__":
    test_emergency_shell_mode()
    print("ok: emergency shell mode")
