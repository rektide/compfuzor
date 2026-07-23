# status-config.sh — report drift in assembled config drop-ins.
#
# Runs `config.sh --check` to compare CONFIG_OUTPUT against what
# re-assembling the active drop-ins in etc/${CONFIG_KEY}/ would produce.
# Not-applicable (exit 2) when CONFIG_KEY is unset or config.sh is absent;
# otherwise passes through config.sh's 0 (clean) / 1 (drift), showing the
# diff on drift. Forwarded args (e.g. -q) reach config.sh.
#
# Reporter contract: 0 clean, 1 drift, 2 not-applicable.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.

if [ -z "${CONFIG_KEY:-}" ]; then
  exit 2
fi

script="$DIR/bin/config.sh"
if [ ! -x "$script" ]; then
  exit 2
fi

"$script" --check "$@"
