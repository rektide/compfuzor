set -euo pipefail
# The launcher reads a systemd credential below; never trace the secret into
# the journal even if its generated caller enabled V>2 xtrace.
case $- in *x*) set +x ;; esac

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

# OPENCODE_SERVE_ARGS is the complete serve argument vector baked by
# bin/build-env-serve-args.sh at build time (--hostname, --port, one --cors
# per discovered origin). It rides the unit's EnvironmentFile; this script
# word-splits it into exec argv because systemd cannot — ExecStart ${VAR}
# expansion passes the whole value as a single argument.
#
# Drop-in plan (mechanism verified on systemd 262): when the opencode-args
# feature line (~/src/opencode-args) is composed and deployed with
# OPENCODE_PASSWORD_FILE support, this wrapper is deleted. systemd expands
# ${CREDENTIALS_DIRECTORY} in ExecStart argv but not in Environment=, so the
# unit becomes:
#   ExecStart=/usr/bin/env \
#     OPENCODE_PASSWORD_FILE=${CREDENTIALS_DIRECTORY}/OPENCODE_PASSWORD \
#     <binary> serve
# with the credential export above gone and the baked vector moved to the
# variable the CLI parses natively — paired with filtering serve-scoped arg
# variables from the session env so tool shells do not inherit them.
serve_args=${OPENCODE_SERVE_ARGS:?OPENCODE_SERVE_ARGS is not set: run build.sh (or bin/build-env-serve-args.sh) to bake the serve arguments}
read -r -a serve_argv <<<"$serve_args"

exec "$binary" serve "${serve_argv[@]}"
