set -euo pipefail

credential_dir=${CREDENTIALS_DIRECTORY:?systemd did not provide the OpenCode credential}
credential=$credential_dir/OPENCODE_PASSWORD
[[ -r $credential ]] || {
  printf 'error: OpenCode password credential is not readable: %s\n' "$credential" >&2
  exit 1
}

OPENCODE_PASSWORD=
IFS= read -r OPENCODE_PASSWORD < "$credential" || [[ -n $OPENCODE_PASSWORD ]]
[[ -n $OPENCODE_PASSWORD ]] || {
  printf 'error: OpenCode password credential is empty\n' >&2
  exit 1
}
export OPENCODE_PASSWORD

binary=${OPENCODE_BINARY:-/usr/local/bin/opencode2}
exec "$binary" serve \
  --hostname "${OPENCODE_SERVER_HOSTNAME:?OPENCODE_SERVER_HOSTNAME is not set}" \
  --port "${OPENCODE_SERVER_PORT:?OPENCODE_SERVER_PORT is not set}"
