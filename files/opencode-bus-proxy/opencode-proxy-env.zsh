# Endpoint metadata only; native service publication/discovery owns routing.
# Keep this module's identity so importing replaces older routing modules.
# The exact client projection is literal data. Its unconditional export is
# deliberately gated here: this module's established policy defaults empty
# AND unset URLs, unlike generic env-zsh's unset-only policy. Missing assembly
# is a prerequisite failure, not a fallback to a separately rendered endpoint.
if [[ -z ${OPENCODE_PROXY_URL:-} ]]; then
  source {{ (ETC ~ '/env-projections/proxy-client.env.export') | quote }} || return $?
fi
export OPENCODE_PROXY_URL
