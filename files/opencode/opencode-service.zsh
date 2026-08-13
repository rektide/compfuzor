# Route interactive clients to the systemd-owned V2 server. Administrative
# service commands and explicit connection choices always pass through.
_opencode_managed() {
  local binary=/usr/local/bin/opencode2
  local arg url password attempt

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

  url=$(command "$binary" service status 2>/dev/null) || url=
  if [[ -z $url ]] && command systemctl --user start opencode.service 2>/dev/null; then
    for attempt in {1..50}; do
      url=$(command "$binary" service status 2>/dev/null) || url=
      [[ -n $url ]] && break
      sleep 0.1
    done
  fi
  password=$(command "$binary" service get password 2>/dev/null) || password=
  if [[ -n $url && -n $password ]]; then
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
