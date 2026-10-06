# Installation is deliberately an operator build action, not a render/timer.
cd {{ HOMEDIR | quote }}
{{ RUST_STORAGE_MISE_BIN | quote }} install {{ item.tool | quote }}
installed=$({{ RUST_STORAGE_MISE_BIN | quote }} where {{ item.tool | quote }})
executable="$installed/bin/{{ item.executable }}"
if [ ! -x "$executable" ]; then
    printf 'Installed executable missing: %s\n' "$executable" >&2
    exit 1
fi
ln -sfnT -- "$executable" {{ (BINS_DIR ~ '/' ~ item.executable) | quote }}
{% if item.cache_dir is defined %}
mkdir -p -- {{ item.cache_dir | quote }}
{% endif %}
