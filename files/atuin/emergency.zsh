# Atuin's contribution to Compfuzor's reversible emergency shell mode.

_emergency_atuin() {
  emulate -L zsh
  local mode=${1:?emergency mode must be on or off}
  local systemctl=${ATUIN_EMERGENCY_SYSTEMCTL:-${commands[systemctl]-}}

  case $mode in
    on)
      if (( ! ${+_COMPFUZOR_EMERGENCY_ATUIN_ACTIVE} )); then
        typeset -g _COMPFUZOR_EMERGENCY_ATUIN_ACTIVE=1
        typeset -gA _COMPFUZOR_EMERGENCY_ATUIN_HOOKS=()
        typeset -g _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY_SET=${+ZSH_AUTOSUGGEST_STRATEGY}
        typeset -ga _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY=("${(@)ZSH_AUTOSUGGEST_STRATEGY}")

        if (( ${preexec_functions[(Ie)_atuin_preexec]} )); then
          _COMPFUZOR_EMERGENCY_ATUIN_HOOKS[preexec]=1
          preexec_functions=("${(@)preexec_functions:#_atuin_preexec}")
        fi
        if (( ${precmd_functions[(Ie)_atuin_precmd]} )); then
          _COMPFUZOR_EMERGENCY_ATUIN_HOOKS[precmd]=1
          precmd_functions=("${(@)precmd_functions:#_atuin_precmd}")
        fi
        if (( ${zshaddhistory_functions[(Ie)_atuin_zshaddhistory]} )); then
          _COMPFUZOR_EMERGENCY_ATUIN_HOOKS[zshaddhistory]=1
          zshaddhistory_functions=("${(@)zshaddhistory_functions:#_atuin_zshaddhistory}")
        fi
      fi

      ZSH_AUTOSUGGEST_STRATEGY=("${(@)ZSH_AUTOSUGGEST_STRATEGY:#atuin}")
      ATUIN_HISTORY_ID=''
      if [[ -n $systemctl ]] && ! "$systemctl" --user stop --no-block \
        atuin-daemon.service atuin-daemon.socket >/dev/null 2>&1; then
        print -u2 'atuin emergency: failed to stop atuin-daemon units'
        return 1
      fi
      ;;
    off)
      (( ${+_COMPFUZOR_EMERGENCY_ATUIN_ACTIVE} )) || return 0

      if (( _COMPFUZOR_EMERGENCY_ATUIN_STRATEGY_SET )); then
        ZSH_AUTOSUGGEST_STRATEGY=("${(@)_COMPFUZOR_EMERGENCY_ATUIN_STRATEGY}")
      else
        unset ZSH_AUTOSUGGEST_STRATEGY
      fi
      if [[ ${_COMPFUZOR_EMERGENCY_ATUIN_HOOKS[preexec]-} == 1 ]] \
        && (( ${+functions[_atuin_preexec]} )) \
        && (( ! ${preexec_functions[(Ie)_atuin_preexec]} )); then
        preexec_functions+=(_atuin_preexec)
      fi
      if [[ ${_COMPFUZOR_EMERGENCY_ATUIN_HOOKS[precmd]-} == 1 ]] \
        && (( ${+functions[_atuin_precmd]} )) \
        && (( ! ${precmd_functions[(Ie)_atuin_precmd]} )); then
        precmd_functions+=(_atuin_precmd)
      fi
      if [[ ${_COMPFUZOR_EMERGENCY_ATUIN_HOOKS[zshaddhistory]-} == 1 ]] \
        && (( ${+functions[_atuin_zshaddhistory]} )) \
        && (( ! ${zshaddhistory_functions[(Ie)_atuin_zshaddhistory]} )); then
        zshaddhistory_functions+=(_atuin_zshaddhistory)
      fi

      unset _COMPFUZOR_EMERGENCY_ATUIN_ACTIVE
      if [[ -n $systemctl ]] && ! "$systemctl" --user start --no-block \
        atuin-daemon.socket >/dev/null 2>&1; then
        print -u2 'atuin emergency: failed to start atuin-daemon.socket'
        return 1
      fi
      ;;
    *)
      print -u2 "_emergency_atuin: expected on or off, got: $mode"
      return 2
      ;;
  esac
}
