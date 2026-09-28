# Legacy boundary-aware shell wrapper, retained as an opt-in fallback for an
# older CLI. Load opencode-client-env.zsh first; it owns credentials and the
# scalar OPENCODE_ARGS default. This file only converts those defaults to argv.

# Route interactive clients read-only through OpenCode's explicit-server path.
# Administrative service commands and explicit connection choices remain the
# upstream default/fallback world; their lifecycle is not delegated to systemd.
_opencode_run() {
  local binary=${OPENCODE_BINARY:-/usr/local/bin/opencode}
  local arg top
  local -i index=1
  local -a server_args routed

  # The client environment module owns OPENCODE_ARGS. This legacy wrapper
  # consumes its shell-word value, then clears it for the child after placing
  # those defaults at the command parser boundary.
  if (( ! ${+OPENCODE_ARGS} )); then
    print -u2 "opencode: client-env module did not set OPENCODE_ARGS"
    return 1
  fi
  [[ -z $OPENCODE_ARGS ]] || server_args=("${(@z)OPENCODE_ARGS}")

  if [[ ! -x $binary ]]; then
    print -u2 "opencode: V2 client not found at $binary"
    return 127
  fi

  for arg in "$@"; do
    case $arg in
      --server|--server=*|--standalone)
        env OPENCODE_ARGS= "$binary" "$@"
        return
        ;;
    esac
  done

  # effect/cli scopes connection flags to the command that declares them.
  # Find the top-level command after any root flags so --server lands at that
  # parser boundary instead of being blindly prepended.
  while (( index <= $# )); do
    case ${argv[index]} in
      --log-level|--completions|--session|-s|--prompt)
        (( index += 2 ))
        ;;
      --log-level=*|--completions=*|--session=*|--prompt=*|--print-logs|--wizard|--help|-h|--version|-v|--auto|--continue|-c)
        (( index += 1 ))
        ;;
      --)
        break
        ;;
      -*)
        (( index += 1 ))
        ;;
      *)
        top=${argv[index]}
        break
        ;;
    esac
  done

  case $top in
    acp|debug|console|mcp|plugin|pair|serve|service)
      # These commands either are not clients or do not yet accept the
      # explicit-server path. Keep them in the upstream fallback world.
      env OPENCODE_ARGS= "$binary" "$@"
      return
      ;;
  esac

  if [[ -z ${OPENCODE_PASSWORD:-} ]]; then
    print -u2 "opencode: OPENCODE_PASSWORD was not loaded from ${OPENCODE_PASSWORD_FILE:-the configured password file}"
    return 1
  fi

  case $top in
    api|models|stats|export|import|mini|run)
      routed=("${(@)argv[1,index]}" "${server_args[@]}")
      (( index < $# )) && routed+=("${(@)argv[index + 1,-1]}")
      env OPENCODE_ARGS= "$binary" "${routed[@]}"
      ;;
    auth)
      # auth declares connection flags on list/login/logout, one level deeper.
      if (( index < $# )); then
        routed=("${(@)argv[1,index + 1]}" "${server_args[@]}")
        (( index + 1 < $# )) && routed+=("${(@)argv[index + 2,-1]}")
        env OPENCODE_ARGS= "$binary" "${routed[@]}"
      else
        env OPENCODE_ARGS= "$binary" "$@"
      fi
      ;;
    *)
      # No subcommand: this is the full-screen client plus optional directory.
      routed=("${server_args[@]}" "$@")
      env OPENCODE_ARGS= "$binary" "${routed[@]}"
      ;;
  esac
}

opencode() {
  _opencode_run "$@"
}

opencode2() {
  _opencode_run "$@"
}
