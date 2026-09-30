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
