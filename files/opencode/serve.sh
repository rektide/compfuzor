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

binary=${OPENCODE_BINARY:-/usr/local/bin/opencode}

# OPENCODE_SERVER_CORS is a comma-separated origin list maintained in env and
# env.export by bin/build-env-cors.sh (run from build.sh); each origin expands
# into opencode's repeatable --cors flag. Empty means no flags.
cors_args=()
if [[ -n ${OPENCODE_SERVER_CORS:-} ]]; then
  IFS=',' read -r -a cors_origins <<<"$OPENCODE_SERVER_CORS"
  for origin in "${cors_origins[@]}"; do
    if [[ -n $origin ]]; then
      cors_args+=(--cors "$origin")
    fi
  done
fi

exec "$binary" serve \
  --hostname "${OPENCODE_SERVER_HOSTNAME:?OPENCODE_SERVER_HOSTNAME is not set}" \
  --port "${OPENCODE_SERVER_PORT:?OPENCODE_SERVER_PORT is not set}" \
  "${cors_args[@]}"
