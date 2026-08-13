# Route interactive clients to the systemd-owned V2 server. Administrative
# service commands and explicit connection choices always pass through.
_opencode_managed() {
  local binary=/usr/local/bin/opencode2
  local url=${OPENCODE_SERVICE_URL:-http://127.0.0.1:49374}
  local arg password attempt ready

  if [[ ! -x $binary ]]; then
    print -u2 "opencode: V2 client not found at $binary"
    return 127
  fi

  case ${1:-} in
    serve|service)
      command "$binary" "$@"
      return
      ;;
  esac

  for arg in "$@"; do
    case $arg in
      --server|--server=*|--standalone)
        command "$binary" "$@"
        return
        ;;
    esac
  done

  if command systemctl --user cat opencode.service >/dev/null 2>&1; then
    if ! command systemctl --user start opencode.service; then
      print -u2 "opencode: failed to start opencode.service"
      return 1
    fi
    for attempt in {1..50}; do
      password=$(command "$binary" service get password 2>/dev/null) || password=
      if [[ -n $password ]] && OPENCODE_PASSWORD=$password command "$binary" --server "$url" api get /api/health >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 0.1
    done
    if [[ -z $ready ]]; then
      print -u2 "opencode: opencode.service did not become ready at $url"
      print -u2 "opencode: inspect with journalctl --user -u opencode.service -n 100"
      return 1
    fi
  else
    password=$(command "$binary" service get password 2>/dev/null) || password=
  fi
  if [[ -n $password ]]; then
    OPENCODE_PASSWORD=$password command "$binary" --server "$url" "$@"
  else
    command "$binary" "$@"
  fi
}

opencode() {
  _opencode_managed "$@"
}

opencode2() {
  _opencode_managed "$@"
}
