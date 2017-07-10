#!/bin/bash
declare -r ROOT_DIR=/tmp/$USER/
declare -r CODE_DIR=~/control/
declare -r SCRIPT_DIR=~/scripts/
declare -r LOGFILE=$ROOT_DIR/scheduler.handler.log
declare -r ERRLOG=$ROOT_DIR/scheduler.handler.error_log
declare -r TMUX_WINDOW_NAME='scheduler'

function is_running {
	if (( $(pgrep -c -u $USER -f scheduler_handler.sh) > 1 )) ; then
		log 'process already running'
		kill_others
	fi
	log 'starting : no instance found'
	setup_directories
}

function main {
	is_running
	while true ; do
		check
		update
		/bin/bash scheduler.sh
		sleep $(( ( RANDOM % 60 )  + 1 ))
	done
}

function kill_others {
	# kills process and children
	while true; do
		read -ep "Something has gone wrong or you're trying to start a second scheduler_handler.
Do you want to kill scheduler, scheduler_handler and associated MATLAB processes?
[y/N] :" yesno
		case $yesno in
		    [Yy]* )
				log "killing previous scheduler, scheduler_handler and MATLAB processes"
				
				if (( $(pgrep -c -u $USER -f scheduler.sh) > 0 )) ; then
					kill -9 $(pgrep -u $USER -f scheduler.sh) &>/dev/null
				fi

				if (( $(pgrep -c -u $USER MATLAB) > 0 )) ; then
					kill -9 $(pgrep -u $USER MATLAB) &>/dev/null
				fi

				if (( $(pgrep -c -u $USER tmux) > 0 )); then
					echo 'YES'
					if tmux list-windows | grep -q "scheduler"; then
						tmux kill-window -t $TMUX_WINDOW_NAME
						log "killed tmux window $TMUX_WINDOW_NAME"
					fi
				fi

				rm -rf $ROOT_DIR/scheduler.*

				if (( $(pgrep -c -u $USER -f scheduler_handler.sh) > 1 )); then
					kill -9 $SH_ID $(pgrep -u $USER -f scheduler_handler.sh) &>/dev/null
				fi
				
		        break;;
		    	* )
		        echo "Skipped"
		        exit 1
		        break;;
		esac
	done
}

function log {
	echo "[$(date)] : log : scheduler_handler : $1 " | tee -a "$LOGFILE"
}

function error_log {
	echo "[$(date)] : ERR : scheduler_handler : $1 " | tee -a "$ERRLOG"
}

function check {
	if [ -f $ERRLOG ]; then
		log "scheduler handler errors found : quitting"
		cat $ERRLOG
		kill_others
		exit
	elif [ -f $ROOT_DIR/scheduler.error_log ]; then
		log "scheduler errors found : quitting"
		cat $ROOT_DIR/scheduler.error_log
		kill_others
		exit
	fi
}

function clear_log {
	rm -f $LOGFILE
	log "cleared old log file"
}

function setup_directories {
	mkdir -p $ROOT_DIR > /dev/null
	chmod 700 $ROOT_DIR > /dev/null
}

function update {
	if ping -c 1 tourmalet.cs.cf.ac.uk &>/dev/null ; then
		scp max@tourmalet.cs.cf.ac.uk:~/scheduler/scheduler.sh $SCRIPT_DIR >/dev/null
	else
		error_log 'cannot connect to tourmalet'
	fi
	log 'Updated scheduler.sh'
}

function clean_up_exit {
	local exit_code=$?
	log "Stopped with exit code : $exit_code"
}

# catch everything but an exit
trap clean_up_exit EXIT 

main "$@"