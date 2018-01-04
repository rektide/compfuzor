#!/bin/bash

[ -z "$DIR" ] && echo "Need a DIR of root cfssl instance" >&2 && exit 2
[ -n "$DIR" ] && export PATH="$DIR/bin:$PATH"

manifest=$1
_etc="$ETC"
_var="$VAR"
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
[ -z "$defaultParent" ] && echo "default parent: $defaultParent" >&2

# create a line in the env file, and assign that value to _source
exportStanza(){
	# args: FINAL_NAME, source, default-source, default-literal
	local line=""
	local value="$(eval echo "\$$2")"
	[ -z "$value" ] && [ -n "$3" ] && eval value="\$$3"
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
	echo findParent
}

# initialize each ca
echo >&2
echo "initize CAs" >&2
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
	mkdir -p $varDir/{cert,csr}
	mkdir -p $etcDir
	if [ -n "$alias" ]
	then
		ln -sf $varDir $VAR/$alias
		ln -sf $etcDir $ETC/$alias
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
	cat << EOF > $etcDir/env
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
echo >&2
echo "run external" >&2
for row in $(jq -rc '.[]' $manifest)
do
	external=$(echo $row|jq -rc '.external // empty')
	if [ -z "$external" ]
	then
		continue
	fi

	name=$(echo $row|jq -rc '.name // empty')
	[ -z "$name" ] && echo "Need a name for external directory" >&2 && exit 1

	externalDir="$external"
	[[ "$externalDir" == /* ]] || externalDir="$(realpath "$DIR/../$external")"
	[ ! -d "$externalDir" ] && echo "External '$external' not found at '$externalDir'" >&2 && exit 1

	sub=$(echo $row|jq -rc '.externalSub // empty')
	[ ! -z "$sub" ] && sub="/$sub"
	ln -sf "$externalDir/var$sub" "$VAR/$name"
	ln -sf "$externalDir/etc$sub" "$ETC/$name"

done

addJson(){
	# name of variable with json in it
	local agg="$(eval echo \$$1)"
	[ -z "$agg" ] && agg="{}"

	# name of variable with file of json in it
	file="$(eval echo \$$2)"
	# clear if no such file
	[ ! -e "$file" ] && file=""
	# read file
	[ -n "$file" ] && file="$(cat $file)"
	# fallback to minimal json form if something has gone wrong & are empty
	[ -z "$file" ] && file="{}"

	# write value back into aggregate
	eval "$1='$(jq -s ".[0] * .[1]" <(echo $agg) <(echo $file))'"
}

# create cas
echo >&2
echo "create CAs" >&2
for row in $(jq -rc '.[]' $manifest)
do
	# this ought be broken out somehow.
	# i like moving most to ca.sh?

	# no CA to generate, must exist already, is linked
	external="$(echo $row|jq -rc '.external // empty')"
	if [ -z "$external" ]
	then
		continue
	fi

	# extract supplemental records
	name="$(echo $row|jq -rc '.name // empty')"
	# preserve "false" for cn
	cn="$(echo $row|jq -rc 'if .cn != false then .cn // "MAGIC_NONE" else false')"
	# default domain
	defaultDomain="\"${DEFAULT_DOMAIN}\""
	[ ${{ '{' }}#defaultDomain} -eq 2 ] && defaultDomain="empty"
	domain="$(echo $row|jq -rc ".domain // $defaultDomain")"
	
	supplementalCar=""
	ourCar=""
	parentCar=""
	finalCar="{}"

	# default to name
	[ "$cn" = "MAGIC_NONE" ] && cn="$name"
	# if not absolute, add domain
	[ -n "$cn" ] && [[ "$cn" != *"."* ]] && [ -n "$domain" ] && cn="$cn.$domain"
	# supplement CAR with 
	[ -n "$cn" ] && [ "$cn" != "false" ] && supplementalCar+="CN:\"$cn\","
	# trim trailing, wrap json object in it's {}
	supplemental="{${supplemental%?}}"

	# from the parent we need a default CA Request profile
	if [ -e "$_etc/$name/parent" ]  && [ -e "$_etc/$name/parent/env.export" ]
	then
		# source parent
		source "$_etc/$name/parent/env.export" 
		# read car
		[ -e "$CAR" ] && parentCar="$(cat $CAR)"
	fi

	# source our new env
	source $_etc/$name/env
	# load "our" CAR
	[ -e "$CAR" ] && ourCar="$(cat $CAR)"

	# add up all our CAR's
	addJson finalCar parentCar
	addJson finalCar ourCar
	addJson finalCar supplementalCar

	# generate a ca
	ca.sh <(cat $finalCar)
done
ETC=$_etc
VAR=$_var

# sign ca's with parent
# give all consumers links to us
# link owner, and borrow ownership if we can - chown as user of owner
