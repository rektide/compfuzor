# Reversible low-I/O mode for the current shell and shells started from it.

_compfuzor_emergency_noop() { :; }

_emergency_zim() {
  local mode=${1:?emergency mode must be on or off}

  case $mode in
    on)
      if (( ! ${+_COMPFUZOR_EMERGENCY_ZIM_ACTIVE} )); then
        typeset -g _COMPFUZOR_EMERGENCY_ZIM_ACTIVE=1
        typeset -g _COMPFUZOR_EMERGENCY_PROMPT_SET=${+PROMPT}
        typeset -g _COMPFUZOR_EMERGENCY_PROMPT=${PROMPT-}
        typeset -g _COMPFUZOR_EMERGENCY_RPROMPT_SET=${+RPROMPT}
        typeset -g _COMPFUZOR_EMERGENCY_RPROMPT=${RPROMPT-}
        typeset -g _COMPFUZOR_EMERGENCY_PROMPT2_SET=${+PROMPT2}
        typeset -g _COMPFUZOR_EMERGENCY_PROMPT2=${PROMPT2-}
        typeset -g _COMPFUZOR_EMERGENCY_HISTFILE_SET=${+HISTFILE}
        typeset -g _COMPFUZOR_EMERGENCY_HISTFILE=${HISTFILE-}
        typeset -g _COMPFUZOR_EMERGENCY_AUTOSUGGEST_SET=${+_ZSH_AUTOSUGGEST_DISABLED}
        typeset -g _COMPFUZOR_EMERGENCY_AUTOSUGGEST=${_ZSH_AUTOSUGGEST_DISABLED-}
        typeset -g _COMPFUZOR_EMERGENCY_HIGHLIGHT_SET=${+ZSH_HIGHLIGHT_HIGHLIGHTERS}
        typeset -ga _COMPFUZOR_EMERGENCY_HIGHLIGHT=("${(@)ZSH_HIGHLIGHT_HIGHLIGHTERS}")
        typeset -g _COMPFUZOR_EMERGENCY_CORRECT=$options[correct]
        typeset -g _COMPFUZOR_EMERGENCY_CORRECT_ALL=$options[correctall]
        typeset -g _COMPFUZOR_EMERGENCY_HASH_LIST_ALL=$options[hashlistall]
        typeset -g _COMPFUZOR_EMERGENCY_BINDINGS="$(bindkey -L)"
        typeset -ga _COMPFUZOR_EMERGENCY_PRECMD=("${(@)precmd_functions}")
        typeset -ga _COMPFUZOR_EMERGENCY_PREEXEC=("${(@)preexec_functions}")
        typeset -ga _COMPFUZOR_EMERGENCY_CHPWD=("${(@)chpwd_functions}")
        typeset -ga _COMPFUZOR_EMERGENCY_PERIODIC=("${(@)periodic_functions}")
        typeset -ga _COMPFUZOR_EMERGENCY_HISTORY=("${(@)zshaddhistory_functions}")
        typeset -ga _COMPFUZOR_EMERGENCY_EXIT=("${(@)zshexit_functions}")
      fi

      PROMPT='emergency:%~%# '
      RPROMPT=''
      PROMPT2='> '
      unset HISTFILE
      typeset -g _ZSH_AUTOSUGGEST_DISABLED=1
      typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=()
      unsetopt correct correctall hashlistall
      precmd_functions=()
      preexec_functions=()
      chpwd_functions=()
      periodic_functions=()
      zshaddhistory_functions=()
      zshexit_functions=()
      bindkey -d
      bindkey -e
      zle -N _compfuzor_emergency_noop
      bindkey '^I' _compfuzor_emergency_noop
      ;;
    off)
      (( ${+_COMPFUZOR_EMERGENCY_ZIM_ACTIVE} )) || return 0

      if (( _COMPFUZOR_EMERGENCY_PROMPT_SET )); then
        PROMPT=$_COMPFUZOR_EMERGENCY_PROMPT
      else
        unset PROMPT
      fi
      if (( _COMPFUZOR_EMERGENCY_RPROMPT_SET )); then
        RPROMPT=$_COMPFUZOR_EMERGENCY_RPROMPT
      else
        unset RPROMPT
      fi
      if (( _COMPFUZOR_EMERGENCY_PROMPT2_SET )); then
        PROMPT2=$_COMPFUZOR_EMERGENCY_PROMPT2
      else
        unset PROMPT2
      fi
      if (( _COMPFUZOR_EMERGENCY_HISTFILE_SET )); then
        HISTFILE=$_COMPFUZOR_EMERGENCY_HISTFILE
      else
        unset HISTFILE
      fi
      if (( _COMPFUZOR_EMERGENCY_AUTOSUGGEST_SET )); then
        _ZSH_AUTOSUGGEST_DISABLED=$_COMPFUZOR_EMERGENCY_AUTOSUGGEST
      else
        unset _ZSH_AUTOSUGGEST_DISABLED
      fi
      if (( _COMPFUZOR_EMERGENCY_HIGHLIGHT_SET )); then
        ZSH_HIGHLIGHT_HIGHLIGHTERS=("${(@)_COMPFUZOR_EMERGENCY_HIGHLIGHT}")
      else
        unset ZSH_HIGHLIGHT_HIGHLIGHTERS
      fi
      [[ $_COMPFUZOR_EMERGENCY_CORRECT == on ]] && setopt correct || unsetopt correct
      [[ $_COMPFUZOR_EMERGENCY_CORRECT_ALL == on ]] && setopt correctall || unsetopt correctall
      [[ $_COMPFUZOR_EMERGENCY_HASH_LIST_ALL == on ]] && setopt hashlistall || unsetopt hashlistall
      precmd_functions=("${(@)_COMPFUZOR_EMERGENCY_PRECMD}")
      preexec_functions=("${(@)_COMPFUZOR_EMERGENCY_PREEXEC}")
      chpwd_functions=("${(@)_COMPFUZOR_EMERGENCY_CHPWD}")
      periodic_functions=("${(@)_COMPFUZOR_EMERGENCY_PERIODIC}")
      zshaddhistory_functions=("${(@)_COMPFUZOR_EMERGENCY_HISTORY}")
      zshexit_functions=("${(@)_COMPFUZOR_EMERGENCY_EXIT}")
      bindkey -d
      eval "$_COMPFUZOR_EMERGENCY_BINDINGS"

      unset _COMPFUZOR_EMERGENCY_ZIM_ACTIVE
      ;;
    *)
      print -u2 "_emergency_zim: expected on or off, got: $mode"
      return 2
      ;;
  esac
}

_emergency() {
  local requested=${1:-toggle}
  local mode hook
  local -i result=0
  local -a hooks

  if (( $# > 1 )); then
    print -u2 'usage: _emergency [on|off|toggle|status]'
    return 2
  fi

  case $requested in
    status)
      if [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
        print 'emergency: on'
      else
        print 'emergency: off'
      fi
      return
      ;;
    toggle)
      if [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then mode=off; else mode=on; fi
      ;;
    on|off)
      mode=$requested
      ;;
    *)
      print -u2 'usage: _emergency [on|off|toggle|status]'
      return 2
      ;;
  esac

  hooks=(${(ok)functions[(I)_emergency_*]})
  [[ $mode == off ]] && hooks=(${(Oa)hooks})

  [[ $mode == on ]] && typeset -gx COMPFUZOR_EMERGENCY=1
  for hook in $hooks; do
    if ! "$hook" "$mode"; then
      print -u2 "emergency: $hook failed to turn $mode"
      result=1
    fi
  done
  [[ $mode == off ]] && unset COMPFUZOR_EMERGENCY

  if [[ $mode == off && ${_COMPFUZOR_EMERGENCY_COLD:-0} == 1 ]]; then
    unset _COMPFUZOR_EMERGENCY_COLD
    if [[ $options[login] == on ]]; then
      exec "${commands[zsh]:-${SHELL:-/bin/zsh}}" -l
    else
      exec "${commands[zsh]:-${SHELL:-/bin/zsh}}"
    fi
  fi

  return $result
}

if [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
  _emergency on
fi
