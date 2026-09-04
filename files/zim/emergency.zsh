# Reversible low-I/O mode for the current shell and shells started from it.
#
# Convention: a subsystem registers a stateless action pair
# `_emergency_<name>_on` / `_emergency_<name>_off`. The `_emergency`
# dispatcher below owns ALL state (`_COMPFUZOR_EMERGENCY_STATE`, plus the
# exported COMPFUZOR_EMERGENCY flag), discovers the pairs, and calls an
# action only on a real transition -- repeated on/off is cheap, and a
# failed transition stays engaged and retryable. Ordering policy: `zim`
# (this shell integration) engages first and disengages last, so the shell
# is lean before any subsystem does external work, and everything is
# restored before the rich shell returns.
#
#   _emergency [on|off|toggle|status]           whole-shell mode
#   _emergency <name> [on|off|toggle|status]    one subsystem, e.g. atuin
#
# Warm shells (turned on interactively) restore their full snapshot in
# place on off. Cold shells (started while COMPFUZOR_EMERGENCY=1 was
# exported, so zimrc skipped module loading) source this module directly,
# engage at source time, and on a successful off exec a fresh zsh -- the
# full zimrc load is the restore.

(( ${+_COMPFUZOR_EMERGENCY_STATE} )) || typeset -gA _COMPFUZOR_EMERGENCY_STATE

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

_compfuzor_emergency_subsystems() {
  # Print the sorted names of subsystems owning a complete action pair.
  local hook name
  local -a names=()

  for hook in ${(ok)functions[(I)_emergency_*_on]}; do
    name="${hook#_emergency_}"
    name="${name%_on}"
    (( ${+functions[_emergency_${name}_off]} )) || continue
    names+=("$name")
  done
  print -r -- "${(@)names[@]}"
}

_compfuzor_emergency_shown_state() {
  # $1 = subsystem: the recorded state, else the global mode.
  if [[ -n ${_COMPFUZOR_EMERGENCY_STATE[$1]:-} ]]; then
    print -r -- "${_COMPFUZOR_EMERGENCY_STATE[$1]}"
  elif [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
    print -r on
  else
    print -r off
  fi
}

_emergency_zim_on() {
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
    # nounset-safe snapshot: only expand an array that exists
    if (( _COMPFUZOR_EMERGENCY_HIGHLIGHT_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_HIGHLIGHT=("${(@)ZSH_HIGHLIGHT_HIGHLIGHTERS[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_HIGHLIGHT=()
    fi
    typeset -g _COMPFUZOR_EMERGENCY_CORRECT=${options[correct]}
    typeset -g _COMPFUZOR_EMERGENCY_CORRECT_ALL=${options[correctall]}
    typeset -g _COMPFUZOR_EMERGENCY_HASH_LIST_ALL=${options[hashlistall]}
    typeset -g _COMPFUZOR_EMERGENCY_MAIN_KEYMAP="$(bindkey -lL main)"
    typeset -g _COMPFUZOR_EMERGENCY_MAIN_BINDINGS=''
    if [[ $_COMPFUZOR_EMERGENCY_MAIN_KEYMAP == 'bindkey -N main' ]]; then
      _COMPFUZOR_EMERGENCY_MAIN_BINDINGS="$(bindkey -L -M main)"
    fi
    typeset -g _COMPFUZOR_EMERGENCY_KEYMAP="compfuzor-emergency-$$"
    # hook arrays may be unset (nounset shells); snapshot existence too
    typeset -g _COMPFUZOR_EMERGENCY_PRECMD_SET=${+precmd_functions}
    typeset -g _COMPFUZOR_EMERGENCY_PREEXEC_SET=${+preexec_functions}
    typeset -g _COMPFUZOR_EMERGENCY_CHPWD_SET=${+chpwd_functions}
    typeset -g _COMPFUZOR_EMERGENCY_PERIODIC_SET=${+periodic_functions}
    typeset -g _COMPFUZOR_EMERGENCY_HISTORY_SET=${+zshaddhistory_functions}
    typeset -g _COMPFUZOR_EMERGENCY_EXIT_SET=${+zshexit_functions}
    if (( _COMPFUZOR_EMERGENCY_PRECMD_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_PRECMD=("${(@)precmd_functions[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_PRECMD=()
    fi
    if (( _COMPFUZOR_EMERGENCY_PREEXEC_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_PREEXEC=("${(@)preexec_functions[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_PREEXEC=()
    fi
    if (( _COMPFUZOR_EMERGENCY_CHPWD_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_CHPWD=("${(@)chpwd_functions[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_CHPWD=()
    fi
    if (( _COMPFUZOR_EMERGENCY_PERIODIC_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_PERIODIC=("${(@)periodic_functions[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_PERIODIC=()
    fi
    if (( _COMPFUZOR_EMERGENCY_HISTORY_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_HISTORY=("${(@)zshaddhistory_functions[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_HISTORY=()
    fi
    if (( _COMPFUZOR_EMERGENCY_EXIT_SET )); then
      typeset -ga _COMPFUZOR_EMERGENCY_EXIT=("${(@)zshexit_functions[@]}")
    else
      typeset -ga _COMPFUZOR_EMERGENCY_EXIT=()
    fi
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
}

_emergency_zim_off() {
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
  # an originally-UNSET hook array must not come back as a set empty one
  (( _COMPFUZOR_EMERGENCY_PRECMD_SET )) || unset precmd_functions
  (( _COMPFUZOR_EMERGENCY_PREEXEC_SET )) || unset preexec_functions
  (( _COMPFUZOR_EMERGENCY_CHPWD_SET )) || unset chpwd_functions
  (( _COMPFUZOR_EMERGENCY_PERIODIC_SET )) || unset periodic_functions
  (( _COMPFUZOR_EMERGENCY_HISTORY_SET )) || unset zshaddhistory_functions
  (( _COMPFUZOR_EMERGENCY_EXIT_SET )) || unset zshexit_functions
  eval "$_COMPFUZOR_EMERGENCY_MAIN_KEYMAP" || return
  if [[ -n $_COMPFUZOR_EMERGENCY_MAIN_BINDINGS ]]; then
    eval "$_COMPFUZOR_EMERGENCY_MAIN_BINDINGS" || return
  fi
  bindkey -D "$_COMPFUZOR_EMERGENCY_KEYMAP" || return

  unset _COMPFUZOR_EMERGENCY_ZIM_ACTIVE
}

_emergency() {
  local requested=${1:-toggle}
  local subsystem='' mode name
  local -i result=0 known=0
  local -a subsystems others reverse

  if (( $# > 2 )); then
    print -u2 'usage: _emergency [on|off|toggle|status] | <subsystem> [on|off|toggle|status]'
    return 2
  fi

  case $requested in
    on|off|toggle|status)
      mode=$requested
      ;;
    *)
      subsystem=$requested
      mode=${2:-toggle}
      ;;
  esac
  if (( $# == 2 )) && [[ -z $subsystem ]]; then
    print -u2 'usage: _emergency [on|off|toggle|status] | <subsystem> [on|off|toggle|status]'
    return 2
  fi
  case $mode in
    on|off|toggle|status) ;;
    *)
      print -u2 "_emergency: unknown mode: $mode"
      return 2
      ;;
  esac

  if [[ ${_COMPFUZOR_EMERGENCY_COLD:-0} == 1 ]] \
    && ! _compfuzor_emergency_load_hooks; then
    result=1
    [[ $mode == off ]] && return $result
  fi

  subsystems=(${(s: :)"$(_compfuzor_emergency_subsystems)"})

  if [[ -n $subsystem ]]; then
    for name in "${(@)subsystems[@]}"; do
      [[ $name == $subsystem ]] && { known=1; break; }
    done
    if (( ! known )); then
      print -u2 "_emergency: unknown subsystem: $subsystem (available: ${(j:, :)subsystems})"
      return 2
    fi
  fi

  if [[ $mode == toggle ]]; then
    if [[ -n $subsystem ]]; then
      if [[ $(_compfuzor_emergency_shown_state "$subsystem") == on ]]; then
        mode=off
      else
        mode=on
      fi
    elif [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
      mode=off
    else
      mode=on
    fi
  fi

  if [[ $mode == status ]]; then
    if [[ -n $subsystem ]]; then
      print -r -- "${subsystem}: $(_compfuzor_emergency_shown_state "$subsystem")"
      return 0
    fi
    if [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
      print -r -- 'emergency: on'
    else
      print -r -- 'emergency: off'
    fi
    for name in "${(@)subsystems[@]}"; do
      print -r -- "  ${name}: $(_compfuzor_emergency_shown_state "$name")"
    done
    return 0
  fi

  if [[ -n $subsystem ]]; then
    if "_emergency_${subsystem}_${mode}"; then
      _COMPFUZOR_EMERGENCY_STATE[$subsystem]=$mode
    else
      print -u2 "emergency: _emergency_${subsystem}_${mode} failed"
      result=1
    fi
    return $result
  fi

  others=("${(@)subsystems[@]:#zim}")

  if [[ $mode == on ]]; then
    typeset -gx COMPFUZOR_EMERGENCY=1
    if [[ ${_COMPFUZOR_EMERGENCY_STATE[zim]:-off} != on ]]; then
      if _emergency_zim_on; then
        _COMPFUZOR_EMERGENCY_STATE[zim]=on
      else
        print -u2 'emergency: _emergency_zim_on failed'
        result=1
      fi
    fi
    for name in "${(@)others[@]}"; do
      # A missing record means "never transitioned here" (fresh or cold
      # shell): act, so a cold shell engages at source time.
      [[ ${_COMPFUZOR_EMERGENCY_STATE[$name]:-off} == on ]] && continue
      if "_emergency_${name}_on"; then
        _COMPFUZOR_EMERGENCY_STATE[$name]=on
      else
        print -u2 "emergency: _emergency_${name}_on failed"
        result=1
      fi
    done
  else
    reverse=("${(@Oa)others[@]}")
    for name in "${(@)reverse[@]}"; do
      [[ ${_COMPFUZOR_EMERGENCY_STATE[$name]:-on} == off ]] && continue
      if "_emergency_${name}_off"; then
        _COMPFUZOR_EMERGENCY_STATE[$name]=off
      else
        print -u2 "emergency: _emergency_${name}_off failed"
        result=1
        break
      fi
    done
    if (( result == 0 )) && [[ ${_COMPFUZOR_EMERGENCY_STATE[zim]:-on} != off ]]; then
      if _emergency_zim_off; then
        _COMPFUZOR_EMERGENCY_STATE[zim]=off
      else
        print -u2 'emergency: _emergency_zim_off failed'
        result=1
      fi
    fi
    if (( result == 0 )); then
      unset COMPFUZOR_EMERGENCY
      if [[ ${_COMPFUZOR_EMERGENCY_COLD:-0} == 1 ]]; then
        unset _COMPFUZOR_EMERGENCY_COLD
        if [[ ${options[login]} == on ]]; then
          exec "${commands[zsh]:-${SHELL:-/bin/zsh}}" -l
        else
          exec "${commands[zsh]:-${SHELL:-/bin/zsh}}"
        fi
      fi
    fi
  fi

  return $result
}

if [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
  _emergency on
fi
