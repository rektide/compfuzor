# compfuzor/watchman: export WATCHMAN_SOCK for shell clients.
#
# Clients use $WATCHMAN_SOCK to skip `watchman get-sockname`
# (https://facebook.github.io/watchman/docs/socket-interface).
#
# By default do NOT stomp an existing WATCHMAN_SOCK -- it may already be set by
# the systemd user manager (the watchman unit's SYSTEMD_ENV ExecStartPost runs
# `systemctl --user set-environment WATCHMAN_SOCK=...`) or by an outer session.
# Set COMPFUZOR_ENV_OVERWRITE=1 (general compfuzor convention for env-setting
# snippets) to force this generated path.
if [ -z "${WATCHMAN_SOCK:-}" ] || [ -n "${COMPFUZOR_ENV_OVERWRITE:-}" ]; then
  export WATCHMAN_SOCK="{{VAR}}/sock"
fi
