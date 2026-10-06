#!/bin/bash
# One shared setup-only envelope. Never executes authored or installer bodies.
# DIR, capture destination and cwd are supplied by the physically rooted adapter.
readonly _cf_action_runtime="$DIR/bin/compfuzor-runtime.mjs"
readonly _cf_action_root="$DIR"
if [ "${1:-}" = "1" ]; then
{% with item = {'env': True} %}
{% include "_helpers/env" %}
{% endwith %}
fi
cd -- "$2" || exit "$?"
export DIR="$_cf_action_root"
exec "$_cf_action_runtime" actions capture-env "$3"
