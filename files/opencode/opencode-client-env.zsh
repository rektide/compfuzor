#!/usr/bin/env zsh
# Client environment for the operator-managed OpenCode server.
# This local Zim module runs only in interactive clients and instance
# launchers. It exports the 0600 credential: the deployed CLI also reads
# the OPENCODE_PASSWORD_FILE pointer itself, but the export keeps dated
# snapshot binaries that predate pointer support working. The secret
# never reaches env or env.export files.
#
# Client routing needs no environment: the server's --publish
# registration is discovered natively from service-local.json.
if [[ -z ${OPENCODE_PASSWORD:-} && -r ${OPENCODE_PASSWORD_FILE:-} ]]; then
  IFS= read -r OPENCODE_PASSWORD < "$OPENCODE_PASSWORD_FILE"
  export OPENCODE_PASSWORD
fi

# Retire the former module-owned proxy wrapper when re-sourced in an old
# shell. Native clients read the publisher/daemon's contact from discovery.
# Do not remove an unrelated user function: only the old body names this key.
if (( ${+functions[opencode]} )) && [[ ${functions[opencode]} == *OPENCODE_PROXY_URL* ]]; then
  unfunction opencode
fi
