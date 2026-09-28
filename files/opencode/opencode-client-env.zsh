#!/usr/bin/env zsh
# Client environment for the operator-managed OpenCode server.
# This local Zim module runs only in interactive clients and instance
# launchers. OPENCODE_ARGS is deliberately not in ENV/env.export, so the
# systemd `serve` process never receives a client-only server default.
if [[ -z ${OPENCODE_PASSWORD:-} && -r ${OPENCODE_PASSWORD_FILE:-} ]]; then
  IFS= read -r OPENCODE_PASSWORD < "$OPENCODE_PASSWORD_FILE"
  export OPENCODE_PASSWORD
fi

# OpenCode natively parses shell words from OPENCODE_ARGS before CLI routing.
# Preserve explicit user defaults; otherwise target this deployment's server.
if (( ! ${+OPENCODE_ARGS} )); then
  export OPENCODE_ARGS="--server ${OPENCODE_SERVER_URL:?OPENCODE_SERVER_URL is not set}"
fi
