# Atuin's contribution to Compfuzor's reversible emergency shell mode.

typeset _compfuzor_emergency_hook_file=${${(%):-%x}:A}
typeset -a _compfuzor_emergency_hook_files=(
  "${(@s.:.)${COMPFUZOR_EMERGENCY_HOOKS:-}}"
)
if (( ! ${_compfuzor_emergency_hook_files[(Ie)$_compfuzor_emergency_hook_file]} )); then
  typeset -gx COMPFUZOR_EMERGENCY_HOOKS="${COMPFUZOR_EMERGENCY_HOOKS:+${COMPFUZOR_EMERGENCY_HOOKS}:}${_compfuzor_emergency_hook_file}"
fi
unset _compfuzor_emergency_hook_file _compfuzor_emergency_hook_files

_emergency_atuin() {
  emulate -L zsh
  local mode=${1:?emergency mode must be on or off}
  local systemctl=${ATUIN_EMERGENCY_SYSTEMCTL:-${commands[systemctl]-}}

  case $mode in
    on)
      if (( ! ${+_COMPFUZOR_EMERGENCY_ATUIN_ACTIVE} )); then
        typeset -g _COMPFUZOR_EMERGENCY_ATUIN_ACTIVE=1
        typeset -g _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY_SET=${+ZSH_AUTOSUGGEST_STRATEGY}
        typeset -ga _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY=("${(@)ZSH_AUTOSUGGEST_STRATEGY[@]}")
      fi

      ZSH_AUTOSUGGEST_STRATEGY=("${(@)ZSH_AUTOSUGGEST_STRATEGY[@]:#atuin}")
      # Activation itself has an Atuin history ID, but emergency mode removes
      # the matching precmd hook. Discard that incomplete event deliberately.
      ATUIN_HISTORY_ID=''
      if [[ -n $systemctl ]]; then
        "$systemctl" --user stop --no-block \
          atuin-daemon.service atuin-daemon.socket || return
      fi
      ;;
    off)
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
      ;;
    *)
      print -u2 "_emergency_atuin: expected on or off, got: $mode"
      return 2
      ;;
  esac
}
