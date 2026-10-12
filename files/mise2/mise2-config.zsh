# Select mise2's config before zim-mise activates in either shell mode.
# Explicit MISE_CONFIG_DIR remains authoritative for caller-selected contexts.
export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-${MISE2_CONFIG_DIR:-{{mise2_config_dir}}}}"
