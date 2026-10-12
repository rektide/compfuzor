# Client-account routing through the proxy. Imported explicitly by its Zim
# producer; native CLI argument preparation applies this to supported commands
# and lets explicit --server / --standalone choices win.
export OPENCODE_PROXY_URL="${OPENCODE_PROXY_URL:-http://127.0.0.1:{{OPENCODE_BUS_PROXY_PORT}}}"
if [[ -z ${OPENCODE_ARGS:-} ]]; then
  export OPENCODE_ARGS="--server $OPENCODE_PROXY_URL"
fi
