# Reversible low-I/O mode for the current shell and shells started from it.

_compfuzor_emergency_noop() { :; }

_compfuzor_emergency_bind_lean() {
  local keymap=$1

  bindkey -N "$keymap" .safe || return
  bindkey -M "$keymap" -R ' '-'~' self-insert || return
  bindkey -M "$keymap" '^A' beginning-of-line || return
  bindkey -M "$keymap" '^B' backward-char || return
  bindkey -M "$keymap" '^C' send-break || return
  bindkey -M "$keymap" '^D' delete-char || return
  bindkey -M "$keymap" '^E' end-of-line || return
  bindkey -M "$keymap" '^F' forward-char || return
  bindkey -M "$keymap" '^H' backward-delete-char || return
  bindkey -M "$keymap" '^I' _compfuzor_emergency_noop || return
  bindkey -M "$keymap" '^J' accept-line || return
  bindkey -M "$keymap" '^K' kill-line || return
  bindkey -M "$keymap" '^L' clear-screen || return
  bindkey -M "$keymap" '^M' accept-line || return
  bindkey -M "$keymap" '^N' down-line-or-history || return
  bindkey -M "$keymap" '^P' up-line-or-history || return
  bindkey -M "$keymap" '^R' history-incremental-search-backward || return
  bindkey -M "$keymap" '^U' kill-whole-line || return
  bindkey -M "$keymap" '^W' backward-kill-word || return
  bindkey -M "$keymap" '^Y' yank || return
  bindkey -M "$keymap" '^?' backward-delete-char || return
  bindkey -M "$keymap" '^[[A' up-line-or-history || return
  bindkey -M "$keymap" '^[[B' down-line-or-history || return
  bindkey -M "$keymap" '^[[C' forward-char || return
  bindkey -M "$keymap" '^[[D' backward-char || return
  bindkey -M "$keymap" '^[[3~' delete-char || return
  bindkey -M "$keymap" '^[[200~' bracketed-paste || return
  bindkey -A "$keymap" main
}

_compfuzor_emergency_load_hooks() {
  (( ${+_COMPFUZOR_EMERGENCY_HOOKS_LOADED} )) && return 0

  local hook_file
  local -i result=0
  local -a hook_files=("${(@s.:.)${COMPFUZOR_EMERGENCY_HOOKS:-}}")

  for hook_file in "${(@)hook_files[@]}"; do
    [[ -z $hook_file ]] && continue
    source "$hook_file" || result=1
  done
  (( result == 0 )) && typeset -g _COMPFUZOR_EMERGENCY_HOOKS_LOADED=1
  return $result
}

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
        typeset -ga _COMPFUZOR_EMERGENCY_HIGHLIGHT=("${(@)ZSH_HIGHLIGHT_HIGHLIGHTERS[@]}")
        typeset -g _COMPFUZOR_EMERGENCY_CORRECT=${options[correct]}
        typeset -g _COMPFUZOR_EMERGENCY_CORRECT_ALL=${options[correctall]}
        typeset -g _COMPFUZOR_EMERGENCY_HASH_LIST_ALL=${options[hashlistall]}
        typeset -g _COMPFUZOR_EMERGENCY_MAIN_KEYMAP="$(bindkey -lL main)"
        typeset -g _COMPFUZOR_EMERGENCY_MAIN_BINDINGS=''
        if [[ $_COMPFUZOR_EMERGENCY_MAIN_KEYMAP == 'bindkey -N main' ]]; then
          _COMPFUZOR_EMERGENCY_MAIN_BINDINGS="$(bindkey -L -M main)"
        fi
        typeset -g _COMPFUZOR_EMERGENCY_KEYMAP="compfuzor-emergency-$$"
        typeset -ga _COMPFUZOR_EMERGENCY_PRECMD=("${(@)precmd_functions[@]}")
        typeset -ga _COMPFUZOR_EMERGENCY_PREEXEC=("${(@)preexec_functions[@]}")
        typeset -ga _COMPFUZOR_EMERGENCY_CHPWD=("${(@)chpwd_functions[@]}")
        typeset -ga _COMPFUZOR_EMERGENCY_PERIODIC=("${(@)periodic_functions[@]}")
        typeset -ga _COMPFUZOR_EMERGENCY_HISTORY=("${(@)zshaddhistory_functions[@]}")
        typeset -ga _COMPFUZOR_EMERGENCY_EXIT=("${(@)zshexit_functions[@]}")
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
      zle -N _compfuzor_emergency_noop
      _compfuzor_emergency_bind_lean "$_COMPFUZOR_EMERGENCY_KEYMAP"
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
        ZSH_HIGHLIGHT_HIGHLIGHTERS=("${(@)_COMPFUZOR_EMERGENCY_HIGHLIGHT[@]}")
      else
        unset ZSH_HIGHLIGHT_HIGHLIGHTERS
      fi
      [[ $_COMPFUZOR_EMERGENCY_CORRECT == on ]] && setopt correct || unsetopt correct
      [[ $_COMPFUZOR_EMERGENCY_CORRECT_ALL == on ]] && setopt correctall || unsetopt correctall
      [[ $_COMPFUZOR_EMERGENCY_HASH_LIST_ALL == on ]] && setopt hashlistall || unsetopt hashlistall
      precmd_functions=("${(@)_COMPFUZOR_EMERGENCY_PRECMD[@]}")
      preexec_functions=("${(@)_COMPFUZOR_EMERGENCY_PREEXEC[@]}")
      chpwd_functions=("${(@)_COMPFUZOR_EMERGENCY_CHPWD[@]}")
      periodic_functions=("${(@)_COMPFUZOR_EMERGENCY_PERIODIC[@]}")
      zshaddhistory_functions=("${(@)_COMPFUZOR_EMERGENCY_HISTORY[@]}")
      zshexit_functions=("${(@)_COMPFUZOR_EMERGENCY_EXIT[@]}")
      eval "$_COMPFUZOR_EMERGENCY_MAIN_KEYMAP" || return
      if [[ -n $_COMPFUZOR_EMERGENCY_MAIN_BINDINGS ]]; then
        eval "$_COMPFUZOR_EMERGENCY_MAIN_BINDINGS" || return
      fi
      bindkey -D "$_COMPFUZOR_EMERGENCY_KEYMAP" || return

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

  if [[ ${_COMPFUZOR_EMERGENCY_COLD:-0} == 1 ]] \
    && ! _compfuzor_emergency_load_hooks; then
    result=1
    [[ $mode == off ]] && return $result
  fi

  hooks=(${(ok)functions[(I)_emergency_*]})
  hooks=("${(@)hooks[@]:#_emergency_zim}")
  if [[ $mode == on ]]; then
    hooks=(_emergency_zim "${(@)hooks[@]}")
  else
    hooks=("${(@Oa)hooks[@]}" _emergency_zim)
  fi

  [[ $mode == on ]] && typeset -gx COMPFUZOR_EMERGENCY=1
  for hook in "${(@)hooks[@]}"; do
    if ! "$hook" "$mode"; then
      print -u2 "emergency: $hook failed to turn $mode"
      result=1
      [[ $mode == off ]] && break
    fi
  done
  [[ $mode == off && $result == 0 ]] && unset COMPFUZOR_EMERGENCY

  if [[ $mode == off && $result == 0 && ${_COMPFUZOR_EMERGENCY_COLD:-0} == 1 ]]; then
    unset _COMPFUZOR_EMERGENCY_COLD
    if [[ ${options[login]} == on ]]; then
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
