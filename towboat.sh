#!/bin/bash
#######################################################################
## Towboat: Managing docker containers with simple configuration files
#######################################################################
## Author     : Bart Meuris <bart.meuris@gmail.com>
## Version    : 0.1 Alpha
##
#######################################################################
## Todo:
## - Add more commandline options
## - Add environment configuration and load /etc/default/towboat if it
##   exists.
## - Testing
## - More testing
#######################################################################
set -m

#LOGLEVEL=1 # ABORT/FATAL/OK
#LOGLEVEL=2 # ERROR
#LOGLEVEL=3 # WARN
#LOGLEVEL=4 # LOG

CONFIGPATH=${TOWBOAT_CONFIGPATH:-"/etc/towboat/"}
PIPEWORK=${PIPEWORK:-$(which pipework 2>/dev/null)}
PIPEWORK=${PIPEWORK:-"/usr/bin/pipework"}
DOCKER=${DOCKER:-$(which docker 2>/dev/null)}
DOCKER=${DOCKER:-"/usr/bin/docker"}
LOGLEVEL=${LOGLEVEL:-4}

function _log() {
	if [ -z "$1" ]; then
		TYPE="LOG"
	else
		TYPE=$1
		shift 1
	fi
	echo "[$(date +"%Y-%m-%d %H:%M:%S")] $TYPE: $*"
}

function log() {
	[ $LOGLEVEL -lt 4 ] && return
	_log "LOG" "$*"
}
function warn() {
	[ $LOGLEVEL -lt 3 ] && return
	_log "WARN" "$*"
}
function error() {
	[ $LOGLEVEL -lt 2 ] && return
	_log "ERROR" "$*"
}

function ok() {
	[ $LOGLEVEL -lt 1 ] && return
	_log "OK" "$*"
}

function fatal() {
	[ $LOGLEVEL -lt 1 ] && return
	_log "FATAL" "$*"
}
function abort() {
	[ $LOGLEVEL -lt 1 ] && return
	_log "ABORT" "$*"
	exit 1
}

function checkval
{
	VAL=$1
	[ -z "$VAL" ] && VAL="${2:-false}"
	case "$(echo $VAL|tr A-Z a-z)" in
	"false"|"f"|"n"|"0")
		echo "false"
		return 1
		;;
	"true"|"t"|"y"|"1")
		echo "true"
		return 0;
		;;
	*)
		echo $VAL
		;;
	esac
	return 0
}

###################################

function getconfigfiles()
{
	find $CONFIGPATH -maxdepth 1 -name "*.cfg" | sort
}

function printenv()
{
	log "NAME=$NAME"
	log "CONTAINER_HOSTNAME=$CONTAINER_HOSTNAME"
	log "IMAGE=$IMAGE"
	log "CONTAINER_PARAM=$CONTAINER_PARAM"
	log "DOCKER_PARAM=$DOCKER_PARAM"
	log "NETWORK_DISABLED=$NETWORK_DISABLED"
	log "PORTS_ALL=$PORTS_ALL"
	log "PORTS=${PORTS[@]}"
	log "VOLUMES=${VOLUMES[@]}"
	log "VOLUMES_FROM=${VOLUMES_FROM[@]}"
	log "LINKS=${LINKS[@]}"
	log "AUTO_REMOVE=$AUTO_REMOVE"
	log "PW_ENABLED=$PW_ENABLED"
	log "PW_HOSTIF=$PW_HOSTIF"
	log "PW_CONTAINER_IF=$PW_CONTAINER_IF"
	log "PW_IP=$PW_IP"
	log "PW_GATEWAY=$PW_GATEWAY"
	log "PW_MAC=$PW_MAC"
	log "CONTAINER_ENV=${CONTAINER_ENV[@]}"
	log "DOCKER_HOST=$DOCKER_HOST"
	log "DATA_CONTAINER=$DATA_CONTAINER"
	log "MD5=$MD5"
}

function resetenv()
{
	# Settings from config file
	NAME=
	CONTAINER_HOSTNAME=
	IMAGE=
	CONTAINER_PARAM=
	DOCKER_PARAM=
	NETWORK_DISABLED=
	PORTS_ALL=
	PORTS=
	VOLUMES=
	VOLUMES_FROM=
	LINKS=
	AUTO_REMOVE=
	PW_ENABLED=
	PW_HOSTIF=
	PW_CONTAINER_IF=
	PW_IP=
	PW_GATEWAY=
	PW_MAC=
	CONTAINER_ENV=
	DOCKER_HOST=
	DATA_CONTAINER=

	# Internal stuff
	RUN_ID=
	MD5=
}

function loadconfig()
{
	local CFILE CNAME IFIPS
	CFILE=$1
	CNAME=$(echo "$1" | sed -e "s#.*/\(.*\)\.cfg#\1#")
	# Reset the environment
	resetenv
	# Load the config file
	[ ! -f "$CFILE" ] && {
		error "Could not start container $CNAME: $CFILE doesn't exist"
		return 1
	}
	. $CFILE
	# Check the container name
	if [ "$CNAME" != "$NAME" ]; then
		error "Container name and file name do not match: $CFILE -> $NAME"
		resetenv
		return 1
	fi
	if [ -n "$PORTS" ]; then
		local P
		local TMP_PORTS
		local TMPA
		for P in "${PORTS[@]}"; do
			if [ "$(echo $P|grep "^@.*:")" ]; then
				local PIF=$(echo $P | sed -e "s#^@\([^:]*\):.*#\1#")
				local PIP=$(ip addr show $PIF | grep "inet " | awk '{ print $2 }' | sed -e "s#^\(.*\)/.*#\1#")
				TMPA=( "$(echo $P|sed -e "s/^@${PIF}:/${PIP}:/")" )
				IFIPS="${IFIPS} ${PIF}=${TMPA[0]}"
				#log "Interface detected in port mapping: $P: $PIF: $PIP -> $TMPA"
			else
				#log "Static mapping: $P"
				TMPA=( "$P" )
			fi
			TMP_PORTS=( "${TMP_PORTS[@]}" "${TMPA[@]}" )
		done
		PORTS=("${TMP_PORTS[@]}")
		#log "TMP_PORTS: ${TMP_PORTS[@]}"
		#log "IFIPS: $IFIPS"
		#log "PORTS: ${PORTS[@]}"
	fi
	
	# Create the DOCKER_HOST commandline parameter
	[ -n "$DOCKER_HOST" ] && DOCKER_HOST="-H=$DOCKER_HOST"
	
	if [ -n "$IFIPS" ]; then
		MD5=$( (cat ${CFILE} ; echo "$IFIPS") | md5sum | awk '{ print $1 }')
	else
		MD5=$( cat ${CFILE} | md5sum | awk '{ print $1 }')
	fi
	return 0
}


function run_pipework()
{
	local PW_OPT

	[ "$(checkval "$PW_ENABLED" false)" == "false" ] && return 0
	log "$NAME: Pipework enabled"

	[ ! -x "$PIPEWORK" ] && abort "Could not locate Pipework executable ($PIPEWORK)!"
	
	[ -z "$PW_HOSTIF" ] && {
		error "$NAME: Could not start pipework, host interface not defined"
		return 1
	}
	
	[ -n "$PW_CONTAINER_IF" ] && PW_OPT="$PW_OPT -i $PW_CONTAINER_IF"
	
	if [ -z "$PW_IP" ]; then
		PW_IP="dhcp"
	elif [ "$PW_IP" != "dhcp" ]; then
		if [ -z "$(echo $PW_IP)|grep "/[0-9]*$")" ]; then
			warn "No netmask specified, using $PW_IP/24"
			PW_IP="$PW_IP/24"
		fi
		[ -n "$PW_GATEWAY" ] && PW_IP="$PW_IP@$PW_GATEWAY"
	fi

	log "Running pipework: $PIPEWORK $PW_HOSTIF $PW_OPT $RUN_ID $PW_IP $PW_MAC"
	eval "$PIPEWORK $PW_HOSTIF $PW_OPT $RUN_ID $PW_IP $PW_MAC" || return 1
	return 0
}

function find_container() {
	local NOT_RUNNING CONT
	[ "$1" == "-a" ] && {
		NOT_RUNNING=1
		shift 1
	}
	CONT=${1:-$NAME}
	
	ID=$($DOCKER $DOCKER_HOST inspect -format "{{.ID}}" $CONT 2>/dev/null) || return 1
	if [ -z "$NOT_RUNNING" ] && [ "$($DOCKER $DOCKER_HOST inspect -format "{{.State.Running}}" $CONT 2>/dev/null)" != "true" ]; then
		return 1
	fi
	echo $ID
	return 0
}

## Find an environment variable stored in the container metadata
function findenv()
{
	local C D_ENV
	C=0
	while true; do
		D_ENV=$($DOCKER $DOCKER_HOST inspect -format="{{(index .Config.Env $C)}}" $NAME 2>/dev/null)
		C=$(( C + 1))
		[ -z "$D_ENV" ] && return 1
		[ -z "$(echo $D_ENV| grep "^$1=")" ] && continue
		echo $D_ENV|sed -e "s/^$1=\(.*\)$/\1/"
	done
	return 0
}

function check_dependency
{
	if [ -n "$(echo $DEPS_CHECKS|grep "|${1}|")" ]; then
		error "$ORIG_CONTAINER: Circular dependency detected when starting dependency $1"
		error "    Dependencies: ${DEPS_CHECKS}"
		return 1
	fi
	return 0
}

function add_dep_tree()
{
	DEPS_CHECKS="${DEPS_CHECKS}|$1|"
}
function rm_dep_tree()
{
	DEPS_CHECKS=$(echo $DEPS_CHECKS|sed -e "s/|$1|//")
}

## Run a dependency for the current container
function run_dependency()
{
	local ORIG_CONTAINER=$1
	local DEP=$2
	local CFGFILE=
	
	if ! check_dependency "$DEP"; then
		resetenv
		return 1
	fi
	add_dep_tree "$DEP"
	
	CFGFILE=$(getconfigfiles | grep "/${DEP}.cfg\$" | tail -n1)
	if [ -z "$CFGFILE" ]; then
		error "$ORIG_CONTAINER: Dependency '$DEP' does not have a config file"
		resetenv
		return 1
	fi
	startcontainer $CFGFILE || {
		error "$ORIG_CONTAINER: Dependency '$DEP' could not be started"
		resetenv
		return 1
	}
	rm_dep_tree "$DEP"
	return 0
}

## Check dependencies for the current container
function check_dependencies()
{
	local ORIG_CONTAINER DEP DEP_LINKS DEP_VOLUMES_FROM DEP_SET
	ORIG_CONTAINER=$NAME
	DEP_LINKS=$LINKS
	DEP_VOLUMES_FROM=$VOLUMES_FROM
	
	check_dependency "$ORIG_CONTAINER" > /dev/null 2>&1 && {
		## Inject the current container if it did not exist.
		add_dep_tree "$ORIG_CONTAINER"
		DEP_SET=1
	}

	# Check if the 'link' dependencies are running, and start if needed
	for DEP in $DEP_LINKS; do
		if [ -z "$(find_container $DEP)" ]; then
			log "$ORIG_CONTAINER: starting dependency $DEP"
			run_dependency "$ORIG_CONTAINER" "$(echo $DEP|sed -e "s/^\(.*\):.*/\1/")" || {
				resetenv
				return 1
			}
		fi
	done
	
	# Check if the data-volumes dependencies exist, and start if needed
	for DEP in $DEP_VOLUMES_FROM; do
		if [ -z "$(find_container -a $DEP)" ]; then
			log "$ORIG_CONTAINER: creating/starting dependency $DEP"
			run_dependency "$ORIG_CONTAINER" "$DEP" || {
				resetenv
				return 1
			}
		fi
	done
	
	# Remove the current container if it did not exist before.
	[ -n "$DEP_SET" ] && rm_dep_tree "$ORIG_CONTAINER"
	
	# Reload our own config
	loadconfig $(getconfigfiles | grep "/${ORIG_CONTAINER}.cfg\$" | tail -n1) || {
		resetenv
		return 1
	}
	return 0
}

#
function full_start()
{
	local _NAME=$NAME
	local _DOPTS=
	local ETHDEVS
	check_dependencies || {
		fatal "$_NAME NOT STARTED"
		resetenv
		return 1
	}
	_DOPTS="-d -name "$NAME" --hostname ${CONTAINER_HOSTNAME:-$NAME} -e TOWBOAT_CONFIG=$MD5"
	
	## Add networking environment
	if [ "$(checkval "$PW_ENABLED" false)" != "false" ]; then
		if [ "$(checkval "$NETWORK_DISABLED" false)" == "true" ]; then
			ETHDEVS="${PW_CONTAINER_IF:-eth1}"
		elif [ "${PW_CONTAINER_IF}" == "eth0" ]; then
			ETHDEVS="eth0"
		else
			ETHDEVS="eth0 ${PW_CONTAINER_IF:-eth1}"
		fi
	elif [ "$(checkval "$NETWORK_DISABLED" false)" == "true" ]; then
		ETHDEVS=""
	else
		ETHDEVS="eth0"
	fi
	_DOPTS="$_DOPTS -e ETHDEVS='$ETHDEVS'"
	
	## Add the environment
	if [ -n "$CONTAINER_ENV" ]; then
		local E
		for E in "${CONTAINER_ENV[@]}"; do
			_DOPTS="$_DOPTS -e $E"
		done
	fi
	## Add links with other containers
	if [ -n "$LINKS" ]; then
		local L
		for L in "${LINKS[@]}"; do
			_DOPTS="$_DOPTS -link $L"
		done
	fi
	
	# Check the network
	[ "$(checkval "$NETWORK_DISABLED" false)" == "true" ] && _DOPTS="${_DOPTS} -n"
	# Process the ports
	[ "$(checkval "$PORTS_ALL" false)" == "true" ] && _DOPTS="${_DOPTS} -P"
	if [ -n "$PORTS" ]; then
		local P
		for P in "${PORTS[@]}"; do
			_DOPTS="$_DOPTS -p $P"
		done
	fi
	
	## Process the volumes
	if [ -n "$VOLUMES" ]; then
		for V in "${VOLUMES[@]}"; do
			_DOPTS="${_DOPTS} -v $V"
		done
	fi
	if [ -n "$VOLUMES_FROM" ]; then
		for VF in "${VOLUMES_FROM[@]}"; do
			_DOPTS="${_DOPTS} --volumes-from $VF"
		done
	fi
	
	RUN_ID=$(eval "$DOCKER $DOCKER_HOST run $DOCKER_PARAM $_DOPTS $IMAGE $CONTAINER_PARAM") || {
		error "Docker run failed: $DOCKER $DOCKER_HOST run $DOCKER_PARAM $_DOPTS $IMAGE $CONTAINER_PARAM"
		fatal "$NAME NOT STARTED"
		resetenv
		return 1
	}
}

function restart()
{
	local MD5R
	local _NAME=$NAME

	## Assume container is not running
	MD5R=$(findenv TOWBOAT_CONFIG)

	if [ $(checkval $DATA_CONTAINER false) == "true" ]; then
		# Container does not have to run, just exist - which it does if we get here.
		if [ "$MD5R" != "$MD5" ]; then
			warn "$NAME is an existing data-container, and configuration has changed since start, NOT REMOVING."
			log "    MD5 DIFF: $MD5R != $MD5"
		else
			log "$NAME is an existing data-container, no need to start."
		fi
		return 0
	fi

	if [ -z "$MD5R" ]; then
		# TOWBOAT_CONFIG env var not set - not started by towboat?
		warn "$NAME: Not started by Towboat (TOWBOAT_CONFIG env var not found) - restarting..."
		check_dependencies
		[ -z "$MD5" ] && {
			fatal "$_NAME NOT STARTED"
			return 1
		}
		
		RUN_ID=$($DOCKER $DOCKER_HOST start $NAME) || {
			error "$_NAME: docker start failed"
			fatal "$NAME NOT STARTED"
			return 1
		}
	elif [ "$MD5R" == "$MD5" ]; then
		# Same configuration file, just restart if needed
		check_dependencies || {
			error "$_NAME: Dependencies check failed"
			fatal "$_NAME NOT STARTED"
			return 1
		}
		RUN_ID=$($DOCKER $DOCKER_HOST start $NAME) || {
			error "$NAME: docker start failed"
			fatal "$NAME NOT STARTED"
			return 1
		}
	elif [ "$(checkval "$AUTO_REMOVE" false)" == "true" ]; then
		# Autoremove is on, this means first removing the container, then performing a full start
		#log "$NAME: Autoremove enabled, removing old instance before re-creating"
		$DOCKER $DOCKER_HOST rm $NAME >/dev/null || {
			error "$NAME: Autoremove enabled, config updated but remove failed!"
			fatal "$NAME NOT STARTED"
			return 1
		}
		full_start || return 1
	fi
	return 0
}

function containerstatus() {
	loadconfig $1 || return 1
	if [ "$(checkval "$ENABLED" true)" == "false"  ]; then
		if [ -n "$(find_container)" ]; then
			warn "$NAME: Disabled, but running"
		else
			ok "$NAME: Disabled"
		fi
		return 0
	elif [ -n "$(find_container)" ]; then
		ok "$NAME: Running"
	elif [ -n "$(find_container -a)" ]; then
		if [ "$(checkval "$DATA_CONTAINER" false)" == "true" ]; then
			ok "$NAME: Data container exists"
		else
			error "$NAME: Container exists but not running"
			return 1
		fi
	else
		error "$NAME: Container does not exist!"
		return 1
	fi
	return 0
}

function stopcontainer() {
	loadconfig $1 || return 1
	if [ -z "$(find_container)" ]; then
		ok "$NAME: already stopped"
	elif [ -z "$(find_container -a)" ]; then
		warn "$NAME: container does not exist"
	else
		$DOCKER $DOCKER_HOST kill $NAME >/dev/null || {
			error "$NAME: error while stopping the container!"
			return 1
		}
		ok "$NAME: stopped."
	fi
	return 0
}

function startcontainer() {
	[ -n "$(echo $CONTAINERS_STARTED | grep "|$1|")" ] && return 0
	[ -n "$(echo $CONTAINERS_FAILED | grep "|$1|")" ] && {
		warn "'$1' already failed before, not attempting to start it again."
		return 1
	}
	
	#log "Starting container from file: $1"
	loadconfig $1 || return 1
	if [ "$(checkval "$ENABLED" true)" == "false"  ]; then
		return 0
	fi
	
	if [ -n "$(find_container)" ]; then
		# Already running, check if config matches environment
		if [ "$MD5" != "$(findenv TOWBOAT_CONFIG)" ]; then
			if [ "$(checkval "$AUTO_REMOVE" false)" == "true" ]; then
				log "$NAME: config change detected, AUTO_REMOVE enabled, killing old instance."
				$DOCKER $DOCKER_HOST kill $NAME >/dev/null || {
					fatal "$NAME: Could not restart upon config change"
					resetenv
					CONTAINERS_FAILED=="${CONTAINERS_FAILED}|$1|"
					return 1
				}
				restart || {
					CONTAINERS_FAILED=="${CONTAINERS_FAILED}|$1|"
					return 1
				}
			else
				warn "$NAME running, but config changed, AUTO_REMOVE disabled!"
				ok "$NAME running"
				return 0
			fi
		else
			ok "$NAME already running"
			return 0
		fi
	elif [ -n "$(find_container -a)" ]; then
		# Exists but not running
		restart || {
			CONTAINERS_FAILED=="${CONTAINERS_FAILED}|$1|"
			return 1
		}
	else
		# Doesn't exist, 
		full_start || {
			CONTAINERS_FAILED=="${CONTAINERS_FAILED}|$1|"
			return 1
		}
	fi
	run_pipework || {
		error "$NAME applying pipework settings failed - killing and removing container..."
		$DOCKER $DOCKER_HOST kill $NAME >/dev/null || {
			error "$NAME: Could not kill container after pipework failed"
			resetenv
			return 1
		}
		$DOCKER $DOCKER_HOST rm $NAME >/dev/null || {
			error "$NAME: Could not remove killed container after pipework failed"
			resetenv
			return 1
		}
		return 1
	}
	ok "$NAME started."
	CONTAINERS_STARTED="${CONTAINERS_STARTED}|$1|"
}

function towboat_run()
{
	# Commandline parameters passed, these should be specific containers to start
	RUNACTION=$1
	FNC=$2
	shift 2
	[ -z "$FNC" ] && return 2

	if [ -n "$1" ]; then
		FAIL=
		while [ -n "$1" ]; do
			CFGF=$(getconfigfiles | grep "/${1}.cfg\$" | tail -n1)
			[ -z "$CFGF" ] && {
				error "## Container '$1' config file not found in '$CONFIGPATH'!"
				FAIL="$FAIL $1"
				shift 1
				continue
			}
			$FNC $CFGF
			shift 1
		done
		[ -n "$FAIL" ] && {
			error "Failed $RUNACTION: $FAIL"
			return 1
		}
		return 0
	fi
	
	## Process all config files
	CONTAINERS_STARTED=
	CONTAINERS_FAILED=
	for F in $(getconfigfiles); do
		DEPS_CHECKS=
		$FNC $F
	done
	#echo CONTAINERS_STARTED: $CONTAINERS_STARTED
	#echo CONTAINERS_FAILED: $CONTAINERS_FAILED
	[ -n "$CONTAINERS_FAILED" ] && return 1
	return 0
}
function towboat_start()
{
	towboat_run "starting" "startcontainer" $*
	return $?
}

function towboat_status()
{
	towboat_run "checking the status of" "containerstatus" $*
	return $?
}
function towboat_stop()
{
	towboat_run "stopping" "stopcontainer" $*
	return $?
}

##################################################
## Startup

[ ! -x "$DOCKER" ] && abort "Could not locate Docker executable!"
CMD=$1
shift 1
case $CMD in
	start)
		towboat_start $* || exit 1
		;;
	stop)
		towboat_stop $* || exit 1
		;;
	restart)
		towboat_stop $* || exit 1
		towboat_start $* || exit 1
		;;
	status)
		towboat_status $* || exit 1
		;;
	*)
		echo "Usage: $0 start|stop|restart|status"
		exit 1
esac
exit 0