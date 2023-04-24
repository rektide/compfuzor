#!/bin/zsh

# wanted: blockinfile shell-script
[ -n "$DIR" ] || DIR="{{DIR}}"
[ -n "$ASDF_DIR" ] || ASDF_DIR="$DIR"
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
	. "$ASDF_SCRIPT"
else
	echo skipping $RC, already installed
fi

for frag in $(jq -r '.[] | @base64' $DIR/etc/plugins.json)
do
	decode=$(echo $frag | base64 --decode)
	plugin=$(echo $decode | jq -r .name)
	url=$(echo $decode | jq -r '.url // ""')
	version=$(echo $decode | jq -r '.version // ""')

	# install plugins
	if ! asdf list $plugin 1>/dev/null 2>/dev/null
	then
		echo installing plugin $plugin
		asdf plugin add $plugin $url

		if [ "$version" = 'false' ]
		then
			continue
		fi

		if [ "$version" = '' ]
		then
			version=$(asdf latest $plugin)
		fi

		asdf install $plugin $version
		asdf global $plugin $version
	else
		echo skipping plugin $plugin, already installed
	fi
done
