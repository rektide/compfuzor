#!/bin/bash

[ -n "$DIR" ] && export PATH="$DIR/bin:$PATH"

manifest=$1
[ -z "$DEFAULT_DOMAIN" ] && DEFAULT_DOMAIN="{{DEFAULT_DOMAIN|default('')}}"
[ -z "$CA_PARENT" ] && CA_PARENT="{{CA_PARENT|default('')}}"
[ -z "$TYPE" ] && TYPE="{{TYPE|default('')}}"
[ -z "$INSTANCE" ] && INSTANCE="{{INSTANCE|default('')}}"

defaultParent=""
IFS=$'\n'
# extract global facts
for row in $(jq -rc '.[]' $manifest)
do
	_defaultParent="$(echo $row|jq -rc '.default_parent // empty')"
	[ -n "$_defaultParent" ] && defaultParent=$_defaultParent
done

# create a line in the env file, and assign that value to _source
exportStanza(){
	# args: FINAL_NAME, source, default-source
	local line=""
	local value="\$$2"
	[ -z "$value" ] && [ -n "$3" ] && value="\$$3"
	if [ -n "$value" ]
	then
		line="export $1=$value"
	else
		line="# $1="
	fi
	eval "_$2=\"$line\""
}

findExternal(){
	# args: external, externalSub optional
	local ext="$1"
	local extSub="$2"
	local found=""
	if [ -z "$extSub" ]
	then
		[ -e "$DIR/../$ext" ] found="$DIR/../$ext"
		[ -e "$VAR/$ext" ] && found="$VAR/$ext"
	else
		echo OH NO WHAT AM I DOING I FORGOT
	fi
	[ -n "$found" ] && echo $found
}

findParent(){
	# args: 
}

# initialize each ca
for row in $(jq -rc '.[]' $manifest)
do
	name="$(echo $row|jq -rc '.name // empty')"
	parent="$(echo $row|jq -rc '.parent // empty')"
	external="$(echo $row|jq -rc '.external // empty')"
	external_sub="$(echo $row|jq -rc '.external_sub // empty')"
	alias="$(echo $row|jq -rc '.alias // empty')"
	comment="$(echo $row|jq -rc '.comment // empty')"
	domain="$(echo $row|jq -rc '.domain // empty')"
	consumer="$(echo $row|jq -rc '.consumer // empty')"
	hosts="$(echo $row|jq -rc '.hosts // empty')"
	csr="$(echo $row|jq -rc '.csr // empty')"
	car="$(echo $row|jq -rc '.car // empty')"

	if [ -n "$external" ]
	then
		# is external one of our own ca's?
		# is it a parent service?
		# we can't be sure yet because we haven't created all our cas
		continue
	fi

	varDir=$VAR/$name
	etcDir=$ETC/$name

	# create directories
	mkdir -p $varDir
	mkdir -p $etcDir
	if [ -n "$alias" ]
	then
		ln -s $varDir $VAR/$alias
		ln -s $etcDir $ETC/$alias
	fi

	# create certificate-signing-request (csr) and certificate authority request
	[ -n "$csr" ] && echo $csr > $CSR
	[ -n "$car" ] && echo $car > $CAR
	# create etc/parent if exists
	[ -z "$parent" ] && [ -n "$default_parent" ] && parent="$default_parent"
	[ -n "$parent" ] && ln -sf $ETC/$parent $etcDir/parent && ln -sf $VAR/$parent $varDir/parent
	# create env file
	exportStanza PARENT parent defaultParent
	exportStanza EXTERNAL external
	exportStanza EXTERNAL_SUB externalSub
	exportStanza ALIAS alias
	exportStanza DOMAIN domain
	exportStanza CONSUMER consumer
	exportStanza HOSTS hosts
	exportStanza CAR car
	exportStanza CSR csr
	echo << EOF > $etcDir/env
# $comment
export CA_FILE="${CA_FILE-ca}"
export ETC="$etcDir"
export VAR="$varDir"
export CSR="$etcDir/csr.json"
export CAR="$etcDir/$CA_FILE.request.json"
export CA="$varDir/$CA_FILE.pem"
export CA_JSON="$varDir/$CA_FILE.json"
export CA_KEY="$varDir/$CA_FILE-key.pem"
export NAME="$name"
export ALIAS="$alias"
$_parent
$_external
$_externalSub
$_alias
$_domain
$_consumer
$_hosts
$_car
$_csr
EOF

done

# run all external now that 
for row in $(jq -rc '.[]' $manifest)
do
	name=$(echo $row|jq -rc '.name // empty')
	external=$(echo $row|jq -rc '.external // empty')

	if [ -z "$external" ]
	then
		continue
	fi

	# is this external one of our sub-cas
	# is this external is a separate ca service
done

# create cas
for row in $(jq -rc '.[]' $manifest)
do
	name="$(echo $row|jq -rc '.name')"
	external="$(echo $row|jq -rc '.external')"

	if [ -n "$external" ]
	then
		continue
	fi

	varDir="$ETC/$name"

	# source our new env
	source $varDir/env
	# generate a ca
	ca.sh
done

# sign ca's with parent
# give all consumers links to us
# link owner, and borrow ownership if we can - chown as user of owner
