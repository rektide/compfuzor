# Atuin's contribution to Compfuzor's reversible emergency shell mode.
#
# Registers the stateless action pair the `_emergency` dispatcher calls
# (all state lives in the dispatcher), and exports this file's path in
# COMPFUZOR_EMERGENCY_HOOKS so cold emergency shells -- which never loaded
# zimrc, and so never loaded Atuin's integration -- can still source and
# run it. `_emergency_atuin_on` stops the daemon socket (Atuin's shell
# hooks are cleared separately by the zim action's whole-shell snapshot);
# `_emergency_atuin_off` restarts the socket, so a warm shell's restored
# hooks reconnect and a cold shell's fresh zsh load rebinds everything.

typeset _compfuzor_emergency_hook_file=${${(%):-%x}:A}
typeset -a _compfuzor_emergency_hook_files=(
  "${(@s.:.)${COMPFUZOR_EMERGENCY_HOOKS:-}}"
)
typeset _compfuzor_emergency_existing_hook
typeset -i _compfuzor_emergency_hook_registered=0
for _compfuzor_emergency_existing_hook in "${(@)_compfuzor_emergency_hook_files[@]}"; do
  if [[ $_compfuzor_emergency_existing_hook == $_compfuzor_emergency_hook_file ]]; then
    _compfuzor_emergency_hook_registered=1
    break
  fi
done
if (( ! _compfuzor_emergency_hook_registered )); then
  typeset -gx COMPFUZOR_EMERGENCY_HOOKS="${COMPFUZOR_EMERGENCY_HOOKS:+${COMPFUZOR_EMERGENCY_HOOKS}:}${_compfuzor_emergency_hook_file}"
fi
unset _compfuzor_emergency_existing_hook _compfuzor_emergency_hook_file
unset _compfuzor_emergency_hook_files _compfuzor_emergency_hook_registered

_emergency_atuin_on() {
  emulate -L zsh
  local systemctl=${ATUIN_EMERGENCY_SYSTEMCTL:-${commands[systemctl]-}}

  if (( ! ${+_COMPFUZOR_EMERGENCY_ATUIN_ACTIVE} )); then
    typeset -g _COMPFUZOR_EMERGENCY_ATUIN_ACTIVE=1
    typeset -g _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY_SET=${+ZSH_AUTOSUGGEST_STRATEGY}
    if (( _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY=("${(@)ZSH_AUTOSUGGEST_STRATEGY[@]}")
    fi
  fi

  # nounset-safe: an unset strategy has nothing to filter
  if (( ${+ZSH_AUTOSUGGEST_STRATEGY} )); then
    ZSH_AUTOSUGGEST_STRATEGY=("${(@)ZSH_AUTOSUGGEST_STRATEGY[@]:#atuin}")
  fi
  # Activation itself has an Atuin history ID, but emergency mode removes
  # the matching precmd hook. Discard that incomplete event deliberately.
  ATUIN_HISTORY_ID=''
  if [[ -n $systemctl ]]; then
    "$systemctl" --user stop --no-block \
      atuin-daemon.service atuin-daemon.socket || return
  fi
}

_emergency_atuin_off() {
  emulate -L zsh
  local systemctl=${ATUIN_EMERGENCY_SYSTEMCTL:-${commands[systemctl]-}}

  (( ${+_COMPFUZOR_EMERGENCY_ATUIN_ACTIVE} )) || return 0

  if [[ -n $systemctl ]]; then
    "$systemctl" --user start --no-block atuin-daemon.socket || return
  fi
  if (( _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY_SET )); then
    ZSH_AUTOSUGGEST_STRATEGY=("${(@)_COMPFUZOR_EMERGENCY_ATUIN_STRATEGY[@]}")
  else
    unset ZSH_AUTOSUGGEST_STRATEGY
  fi
  unset _COMPFUZOR_EMERGENCY_ATUIN_ACTIVE
}
