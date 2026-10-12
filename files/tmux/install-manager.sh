# Install the shared CONFIG receiver and project one source block into tmux.
# Root-file selection agrees with the existing Ahiru installer and TPM discovery.
set -eu
NAME={{NAME | quote}}
if [ -z "${TMUX_CONF:-}" ]; then
  if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" ]; then
    TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  elif [ -f "$HOME/.tmux.conf" ]; then
    TMUX_CONF="$HOME/.tmux.conf"
  elif [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/tmux" ]; then
    TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  else
    TMUX_CONF="$HOME/.tmux.conf"
  fi
fi

"$DIR/bin/config-install.sh" --definition tmux --context user
PLUGIN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/compfuzor/$NAME/tmux-plugins.conf"
printf 'source-file "%s"\n' "$PLUGIN_CONFIG" |
  block-in-file -n "$NAME-plugins" -o "$TMUX_CONF" --create true --anchor eof:90
block-in-file -n "$NAME-run" -i "$DIR/etc/tmux-run.conf" -o "$TMUX_CONF" --create true --anchor eof:100
