# Installation is deliberately an operator build action, not a render/timer.
cd {{ HOMEDIR | quote }}
{{ RUST_STORAGE_MISE_BIN | quote }} install {{ bin_item.tool | quote }}
installed=$({{ RUST_STORAGE_MISE_BIN | quote }} where {{ bin_item.tool | quote }})
executable="$installed/bin/{{ bin_item.executable }}"
if [ ! -x "$executable" ]; then
    printf 'Installed executable missing: %s\n' "$executable" >&2
    exit 1
fi
ln -sfnT -- "$executable" {{ (BINS_DIR ~ '/' ~ bin_item.executable) | quote }}
{% if bin_item.cache_dir is defined %}
mkdir -p -- {{ bin_item.cache_dir | quote }}
{% endif %}
