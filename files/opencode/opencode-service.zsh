# Load the operator-managed server credential once per shell. Keep the secret
# in its single persisted 0600 file rather than copying it into a ZIM fragment.
if [[ -z ${OPENCODE_PASSWORD:-} && -r ${OPENCODE_PASSWORD_FILE:-} ]]; then
  IFS= read -r OPENCODE_PASSWORD < "$OPENCODE_PASSWORD_FILE"
  export OPENCODE_PASSWORD
fi

# Load the client-only ZIM_ARRAYS defaults here as well as through the host
# roster. This keeps both the shell wrapper and opencode-last on one argv source.
typeset _opencode_args_module=${OPENCODE_ARGS_MODULE:-/etc/opt/opencode-git/zim-modules/opencode-client-args/init.zsh}
[[ ! -r $_opencode_args_module ]] || source "$_opencode_args_module"
unset _opencode_args_module

# Route interactive clients read-only through OpenCode's explicit-server path.
# Administrative service commands and explicit connection choices remain the
# upstream default/fallback world; their lifecycle is not delegated to systemd.
_opencode_run() {
  local binary=${OPENCODE_BINARY:-/usr/local/bin/opencode2}
  local port=${OPENCODE_SERVER_PORT:-49373}
  local url=${OPENCODE_SERVER_URL:-http://127.0.0.1:$port}
  local arg top
  local -i index=1
  local -a server_args routed

  # ZIM_ARRAYS provides OPENCODE_ARGS as a client-shell-only Zsh array. Ignore
  # scalar environment values until native CLI OPENCODE_ARGS support lands.
  if (( ${+OPENCODE_ARGS} )) && [[ ${(t)OPENCODE_ARGS} != *array* ]]; then
    unset OPENCODE_ARGS
  fi
  if (( ${+OPENCODE_ARGS} )) && (( $#OPENCODE_ARGS > 0 )); then
    server_args=("${(@)OPENCODE_ARGS}")
  else
    server_args=(--server "$url")
  fi

  if [[ ! -x $binary ]]; then
    print -u2 "opencode: V2 client not found at $binary"
    return 127
  fi

  for arg in "$@"; do
    case $arg in
      --server|--server=*|--standalone)
        command "$binary" "$@"
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
      command "$binary" "$@"
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
      command "$binary" "${routed[@]}"
      ;;
    auth)
      # auth declares connection flags on list/login/logout, one level deeper.
      if (( index < $# )); then
        routed=("${(@)argv[1,index + 1]}" "${server_args[@]}")
        (( index + 1 < $# )) && routed+=("${(@)argv[index + 2,-1]}")
        command "$binary" "${routed[@]}"
      else
        command "$binary" "$@"
      fi
      ;;
    *)
      # No subcommand: this is the full-screen client plus optional directory.
      routed=("${server_args[@]}" "$@")
      command "$binary" "${routed[@]}"
      ;;
  esac
}

opencode() {
  _opencode_run "$@"
}

opencode2() {
  _opencode_run "$@"
}
