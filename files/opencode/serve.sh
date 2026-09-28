set -euo pipefail

binary=${OPENCODE_BINARY:-/usr/local/bin/opencode}

# OPENCODE_SERVE_ARGS is the complete serve argument vector baked by
# bin/build-env-serve-args.sh at build time (--hostname, --port, one --cors
# per discovered origin). It rides the unit's EnvironmentFile; this script
# word-splits it into exec argv because systemd cannot — ExecStart ${VAR}
# expansion passes the whole value as a single argument.
#
# Interim form: the credential no longer flows through this wrapper. The
# server reads its password from OPENCODE_PASSWORD_FILE — already an ENV
# key, delivered by the unit's EnvironmentFile exactly as to clients —
# which the opencode-args line's env-pointer support consumes. Requires a
# binary carrying that support: do not restart the unit onto an older
# binary or the server boots with an ephemeral password.
#
# Final form (mechanism verified on systemd 262): when the line's
# --password-file flag and serve-route environment argument parsing are
# composed and deployed, this wrapper is deleted. systemd expands the %d
# credentials specifier in ExecStart argv — Environment= cannot compose
# credential paths at all — so the unit regains LoadCredential and runs:
#   ExecStart=<binary> serve --password-file %d/OPENCODE_PASSWORD
# with the baked vector on the variable the CLI parses natively, paired
# with filtering serve-scoped arg variables from the session env so tool
# shells do not inherit them.
serve_args=${OPENCODE_SERVE_ARGS:?OPENCODE_SERVE_ARGS is not set: run build.sh (or bin/build-env-serve-args.sh) to bake the serve arguments}
read -r -a serve_argv <<<"$serve_args"

exec "$binary" serve "${serve_argv[@]}"
