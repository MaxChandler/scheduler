#!/bin/bash
declare -r ROOT_DIR=/tmp/$USER/
declare -r MRS_DIR=/tmp/$USER/MRS_Data/
declare -r CONTROL_DIR=/tmp/$USER/control/
declare -r LOGFILE=$ROOT_DIR/scheduler.log
declare -r ERRLOG=$ROOT_DIR/scheduler.error_log
declare -a RESTRICTED_MACHINES=( "aluminium" "argon" "arsenic" "beryllium" "boron" "bromine" "calcium" "carbon" "chlorine" "chromium" "cobalt" "copper" "fluorine" "gallium" "germanium" "helium" "hydrogen" "iron" "krypton" "lithium" "magnesium" "manganese" "neon" "nickel" "niobium" "nitrogen" "oxygen" "phosphorus" "potassium" "rubidium" "scandium" "selenium" "silicon" "sodium" "strontium" "sulfur" "titanium" "vanadium" "yttrium" "zirconium" "zinc" )
declare -r PROCESS_COMMAND="matlab -nodisplay -r 'add_path_matlab; current_experiment; exit;'"
declare -r TMUX_WINDOW_NAME='scheduler'
declare -r RAM_LIMIT=90

function is_running {
	if [[ -f $ROOT_DIR/scheduler.running ]] ; then
		log 'scheduler already running'
		exit 1
	fi
	log 'starting scheduler : no instance found'
	touch "$ROOT_DIR/scheduler.running"
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

function clean_up {
	rm -f "$ROOT_DIR/scheduler.running"
	log "cleaned up from exit code : $?"
}

function log {
	echo "[$(date)] : scheduler.sh : $1 " | tee -a "$LOGFILE"
}

function error_log {
	echo "[$(date)] : scheduler.sh : ERROR : $1 " | tee -a "$ERRLOG"
}

function clear_log {
	rm -f $LOGFILE
	log "cleared old log file"
}

function warning_log {
	log "WARNING : $1 "
}

function check {
	# consistency checks
	# if there are pre-existing errors, then stop running
	if [ -f $ERRLOG ]; then
		exit
	fi

	# check to make sure we can access the servers we can connect too
	ssh -q max@ventoux.cs.cf.ac.uk exit
	if [[ $? != 0 ]] ; then
		error_log 'cannot open ssh connection to ventoux, but can ping : setup keys'
		exit
	fi

	ssh -q max@mrs1.cs.cf.ac.uk exit
	if [[ $? != 0 ]] ; then
		error_log 'cannot open ssh connection to mrs1, but can ping : setup keys'
		exit
	fi

	# assumed that if you reach here, you can access one of the servers

	# make sure all the programs we need are installed!
	if ! type tmux >/dev/null 2>/dev/null; then
  		error_log "tmux is not installed"
  		exit
	elif ! type matlab >/dev/null 2>/dev/null; then
  		error_log "matlab is not installed"
  		exit
	elif ! type sshfs >/dev/null 2>/dev/null; then
  		error_log "sshfs is not installed"
  		exit
	elif ! type rsync >/dev/null 2>/dev/null; then
  		error_log "rsync is not installed"
  		exit
  	elif ! type ffmpeg >/dev/null 2>/dev/null; then
  		warning_log "ffpmeg is not installed"
  	elif ! type povray >/dev/null 2>/dev/null; then
  		warning_log "povray is not installed"
	fi
	setup_directories
}

function setup_directories {
	mkdir -p $MRS_DIR
	chmod 700 $ROOT_DIR
	log "setup directories : $MRS_DIR & $ROOT_DIR"
}

function mount_sshfs {
	if [ -z "$(ls -A $MRS_DIR)" ]; then
		sshfs max@ventoux.cs.cf.ac.uk:/media/raid/MRS_Data/ $MRS_DIR
		log "Mounted ventoux SSHFS to $MRS_DIR"
	fi
}

function unmount_sshfs {
	if ! [ -z "$(ls -A $MRS_DIR)" ]; then
		fusermount -u $MRS_DIR
		log "Unmounted SSHFS : $MRS_DIR"
	fi
}

function update_repository {
	log "updating code repository : $CONTROL_DIR"
	if ! pgrep -u $USER -x "MATLAB" > /dev/null ; then
		if ! pgrep -x "rsync" -u $USER > /dev/null; then
			if ping -c 1 -w 3 mrs1.cs.cf.ac.uk &>/dev/null ; then
				log "rsyncing with : mrs1"
				if is_restricted_machine ; then 
					log 'restricted  machine : nice and ionice used to rsync'
					nice -n 19 ionice -c2 -n7 rsync -r --delete --force max@mrs1.cs.cf.ac.uk:~/control/ $CONTROL_DIR
				else
					rsync -r --delete --force max@mrs1.cs.cf.ac.uk:~/control/ $CONTROL_DIR
				fi
			elif ping -c 1 -w 3 ventoux.cs.cf.ac.uk &>/dev/null ; then
				log "couldn't connect to mrs1 : rsyncing with : ventoux"
				if is_restricted_machine ; then	
					log 'restricted  machine : nice and ionice used to rsync'
					nice -n 19 ionice -c2 -n7 rsync -r --delete --force max@ventoux.cs.cf.ac.uk:~/control/ $CONTROL_DIR
				else
					rsync -r --delete --force max@ventoux.cs.cf.ac.uk:~/control/ $CONTROL_DIR
				fi
			else
				error_log 'Cannot contact mrs1 or ventoux to update repository'
			fi
		fi
		log 'code updated successfully'
	else
		log 'matlab is running : not updating'
	fi
}

function kill_processes {
	if pgrep -u $USER "MATLAB" > /dev/null ; then
		pkill -u $USER "MATLAB"
		log 'Killed MATLAB'
	fi
	if  tmux list-windows | grep "$TMUX_WINDOW_NAME">/dev/null; then
		tmux kill-window -t $TMUX_WINDOW_NAME
		log "killed tmux window $TMUX_WINDOW_NAME"
	fi
	unmount_sshfs
	exit
}

function start_processes {
	mount_sshfs
	update_repository
	if ! tmux ls >/dev/null; then
		tmux new-session -d
		log "starting tmux session"
	fi

	if ! pgrep -u $USER -x "MATLAB" > /dev/null ; then
		log 'MATLAB & tmux now running : starting job'
		if ! tmux list-windows | grep "$TMUX_WINDOW_NAME">/dev/null; then
			log "starting tmux window with name : $TMUX_WINDOW_NAME"
			tmux new-window -n "$TMUX_WINDOW_NAME"
		fi
		if is_restricted_machine ; then
			log "Restricted machine : running job with nice -n 19 & ionice -c 2 -n 7 : $PROCESS_COMMAND"
			tmux send-keys -t "$TMUX_WINDOW_NAME" "cd $CONTROL_DIR/QControl/; nice -n 19 ionice -c2 -n7 $PROCESS_COMMAND" C-m
		else
			log "Unrestricted machine : running job : $PROCESS_COMMAND"
			tmux send-keys -t "$TMUX_WINDOW_NAME" "cd $CONTROL_DIR/QControl/; $PROCESS_COMMAND" C-m
		fi
	else
		log 'MATLAB is already running : not starting another job!'
	fi
}

function has_finished {
	# if matlab is no longer running, then it's assumed the job is done!
	if ! pgrep -u $USER -x "MATLAB" > /dev/null ; then
		log "MATLAB is no longer running : job must be complete!"
		kill_processes
	fi
	return 1
}

function is_restricted_machine {
	for machine in ${RESTRICTED_MACHINES[@]} ; do
		if [[ "$machine" == "$HOSTNAME" ]]; then
			return 0
		fi
	done
	return 1
}

function main {
	is_running
	clear_log
	check
	while true ; do
		if is_restricted_machine ; then
			log "Running on a machine that is restricted in computing time & resources"
			local H=$(date +%H)
			# if (( 8 <= 10#$H && 10#$H < 18 )); then 
			# 	# kill matlab, tmux and sshfs
			#     log 'between 8AM and 6PM : killing processes'
			#     kill_processes
			# else
				# start tmux, attach sshfs, update tmp and matlab
				# log 'between 8AM and 6PM'
				num_users=$( who | sort --key=1,1 --unique | wc --lines )
				if (( $num_users > 1 )); then
					# kill everything
					log 'more than one user logged in : killing process'
					kill_processes
				elif [[ $( free -m | awk 'NR==2{printf "%.f", $3*100/$2 }') > $RAM_LIMIT ]] ; then
					log "memory usage is higher than $RAM_LIMIT percent, killng process"
					kill_processes
				else
					# start and run!
					log 'one user logged in : starting process'
					start_processes
				fi
			# fi
		else
			log "Unrestricted machine : attempting to start process"
			start_processes
		fi
		sleep $(( ( RANDOM % 300 )  + 1 ))
		has_finished
	done
}

trap clean_up INT TERM SIGHUP SIGINT SIGTERM SIGQUIT
trap clean_up_exit EXIT
main "$@"
