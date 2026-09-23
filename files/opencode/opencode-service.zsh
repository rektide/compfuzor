# Load the operator-managed server credential once per shell. Keep the secret
# in its single persisted 0600 file rather than copying it into a ZIM fragment.
if [[ -z ${OPENCODE_PASSWORD:-} && -r ${OPENCODE_PASSWORD_FILE:-} ]]; then
  IFS= read -r OPENCODE_PASSWORD < "$OPENCODE_PASSWORD_FILE"
  export OPENCODE_PASSWORD
fi

# Route interactive clients read-only through OpenCode's explicit-server path.
# Administrative service commands and explicit connection choices remain the
# upstream default/fallback world; their lifecycle is not delegated to systemd.
_opencode_run() {
  local binary=${OPENCODE_BINARY:-/usr/local/bin/opencode2}
  local url=${OPENCODE_SERVER_URL:-http://127.0.0.1:49373}
  local arg top
  local -i index=1
  # Keep the command line as an argument vector, never a shell-split string.
  # The native CLI OPENCODE_ARGS environment feature is a separate, not-started
  # working-set patch; this array is local to the wrapper for now.
  local -a OPENCODE_ARGS

  if [[ ! -x $binary ]]; then
    print -u2 "opencode: V2 client not found at $binary"
    return 127
  fi

  for arg in "$@"; do
    case $arg in
      --server|--server=*|--standalone)
        OPENCODE_ARGS=("$@")
        command "$binary" "${OPENCODE_ARGS[@]}"
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
      OPENCODE_ARGS=("$@")
      command "$binary" "${OPENCODE_ARGS[@]}"
      return
      ;;
  esac

  if [[ -z ${OPENCODE_PASSWORD:-} ]]; then
    print -u2 "opencode: OPENCODE_PASSWORD was not loaded from ${OPENCODE_PASSWORD_FILE:-the configured password file}"
    return 1
  fi

  case $top in
    api|models|stats|export|import|mini|run)
      OPENCODE_ARGS=("${(@)argv[1,index]}" --server "$url")
      (( index < $# )) && OPENCODE_ARGS+=("${(@)argv[index + 1,-1]}")
      command "$binary" "${OPENCODE_ARGS[@]}"
      ;;
    auth)
      # auth declares connection flags on list/login/logout, one level deeper.
      if (( index < $# )); then
        OPENCODE_ARGS=("${(@)argv[1,index + 1]}" --server "$url")
        (( index + 1 < $# )) && OPENCODE_ARGS+=("${(@)argv[index + 2,-1]}")
        command "$binary" "${OPENCODE_ARGS[@]}"
      else
        OPENCODE_ARGS=("$@")
        command "$binary" "${OPENCODE_ARGS[@]}"
      fi
      ;;
    *)
      # No subcommand: this is the full-screen client plus optional directory.
      OPENCODE_ARGS=(--server "$url" "$@")
      command "$binary" "${OPENCODE_ARGS[@]}"
      ;;
  esac
}

opencode() {
  _opencode_run "$@"
}

opencode2() {
  _opencode_run "$@"
}
