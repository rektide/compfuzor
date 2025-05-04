#!/bin/zsh

# wanted: blockinfile shell-script
[ -n "$ASDF_DIR" ] || ASDF_DIR="{{DIR}}"
[ -n "$ASDF_DATA_DIR" ] || ASDF_DATA_DIR="$ASDF_DIR/var/data"
[ -n "$RC" ] || RC=~/.zshrc

# install in $RC if not existing
if ! grep -q asdf.sh $RC
then
	echo installing asdf in $RC
	cat << EOF >> $RC
[ -z "\$ASDF_DATA_DIR" ] && export ASDF_DATA_DIR="$ASDF_DATA_DIR"
export PATH="\${ASDF_DATA_DIR:-\$HOME/.asdf}/shims:\$PATH"
# append completions to fpath
#fpath=(\${ASDF_DIR}/completions \$fpath)
# initialise completions with ZSH's compinit
#autoload -Uz compinit && compinit
EOF
else
	echo skipping $RC, already installed
fi

for frag in $(jq -r '.[] | @base64' $ASDF_DIR/etc/plugins.json)
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

	else
		echo skipping plugin $plugin, already installed
	fi

	if [ "$version" = 'false' ]
	then
		continue
	fi

	if [ "$version" = '' ]
	then
		version=$(asdf latest $plugin)
	fi

	if [ -n "$version" ]
	then
		asdf install $plugin $version
	else 
      echo skipping latest for $plugin
	fi
done
