#!/bin/sh

# wanted: blockinfile shell-script
[ -n "$ASDF_DIR" ] || ASDF_DIR="{{DIR}}"
[ -n "$ASDF_SCRIPT" ] || ASDF_SCRIPT="${ASDF_DIR}/asdf.sh"
[ -n "$RC" ] || RC=~/.zshrc

# install in $RC if not existing
if ! grep -q asdf.sh $RC
then
	echo installing asdf in $RC
	cat << EOF >> $RC
. "$ASDF_SCRIPT"
# append completions to fpath
#fpath=(${ASDF_DIR}/completions $fpath)
# initialise completions with ZSH's compinit
#autoload -Uz compinit && compinit
EOF
else
	echo skipping $RC, already installed
fi

# install plugins
{% for plugin, url in plugins.items() -%}
if ! asdf list {{plugin}} 1>/dev/null 2>/dev/null
then
	echo installing plugin {{plugin}}
	asdf plugin add {{plugin}} {{url}}
else
	echo skipping plugin {{plugin}}, already installed
fi
{% endfor %}
