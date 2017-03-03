#!/bin/bash
declare -r ROOT_DIR=/tmp/$USER/
declare -r CODE_DIR=~/control/
declare -r SCRIPT_DIR=~/scripts/
declare -r LOGFILE=$ROOT_DIR/scheduler.handler.log
declare -r ERRLOG=$ROOT_DIR/scheduler.handler.error_log

function main {
	is_running
	while true ; do
		check
		update
		/bin/bash scheduler.sh
		sleep 120
	done
}

function log {
	echo "[$(date)] : scheduler_handler.sh : $1 " | tee -a "$LOGFILE"
}

function error_log {
	echo "[$(date)] : scheduler_handler.sh :ERROR : $1 " | tee -a "$ERRLOG"
}

function check {
	if [ -f $ERRLOG ]; then
		echo "scheduler handler errors found : quitting"
		exit
	elif [ -f $ROOT_DIR/scheduler.error_log ]; then
		echo "scheduler errors found : quitting"
		exit
	fi
}

function clear_log {
	rm -f $LOGFILE
	log "cleared old log file"
}

function setup_directories {
	mkdir -p $ROOT_DIR
	chmod 700 $ROOT_DIR
}

function update {
	if ping -c 1 mrs1.cs.cf.ac.uk &>/dev/null ; then
		scp max@mrs1.cs.cf.ac.uk:~/scheduler/scheduler.sh $SCRIPT_DIR >/dev/null
	elif ping -c 1 ventoux.cs.cf.ac.uk &>/dev/null ; then
		scp max@ventoux.cs.cf.ac.uk:~/scheduler/scheduler.sh $SCRIPT_DIR >/dev/null
	else
		error_log 'cannot connect to mrs1 or ventoux'
	fi
	log 'Updated scheduler.sh'
}

function clean_up {
	rm -f "$ROOT_DIR/scheduler.handler.running"
	exit
}

function clean_up_exit {
	# if we have exit code 1, it's because the script has been called when it's already running. We don't want to remove the lockfile!
	local exit_code=$?
	if [[ $exit_code == 0 ]] ; then
		rm -f "$ROOT_DIR/scheduler.running"
		log "removed lock file"
	else
		log "lock file left in place"
	fi
	log "Stopped with exit code : $exit_code"
}

function is_running {
	if [[ -f $ROOT_DIR/scheduler.running ]] ; then
		log 'process already running'
		exit 1
	else
		setup_directories
		touch "$ROOT_DIR/scheduler.handler.running"
	fi
}

# catch everything but an exit
trap clean_up INT TERM SIGHUP SIGINT SIGTERM SIGQUIT
trap clean_up_exit EXIT

main "$@"
