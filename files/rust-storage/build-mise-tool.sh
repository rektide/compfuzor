# Installation is deliberately an operator build action, not a render/timer.
cd {{ HOMEDIR | quote }}
{{ RUST_STORAGE_MISE_BIN | quote }} install {{ bin_item.tool | quote }}
installed=$({{ RUST_STORAGE_MISE_BIN | quote }} where {{ bin_item.tool | quote }})
installed=$(readlink -f -- "$installed")
# Aqua archive layouts vary; ask the backend rather than assume bin/<tool>.
executable=$({{ RUST_STORAGE_MISE_BIN | quote }} which {{ bin_item.executable | quote }} --tool {{ bin_item.tool | quote }})
executable=$(readlink -f -- "$executable")
case "$executable" in
    "$installed"/*) ;;
    *) printf 'Executable is outside the pinned mise installation: %s\n' "$executable" >&2; exit 1 ;;
esac
if [ ! -x "$executable" ]; then
    printf 'Installed executable missing: %s\n' "$executable" >&2
    exit 1
fi
ln -sfnT -- "$executable" {{ (BINS_DIR ~ '/' ~ bin_item.executable) | quote }}
{% if bin_item.cache_dir is defined %}
mkdir -p -- {{ bin_item.cache_dir | quote }}
{% endif %}
