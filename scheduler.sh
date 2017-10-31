#!/bin/bash
declare -r ROOT_DIR=/tmp/$USER/
declare -r MRS_LOCAL_DIR=/tmp/$USER/MRS_Data/
declare -r MRS_REMOTE_HOST=max@tourmalet.cs.cf.ac.uk
declare -r MRS_REMOTE_DIR=/home/max/MRS_Data/
declare -r CONTROL_DIR=/tmp/$USER/control/
declare -r LOGFILE=${ROOT_DIR}scheduler.log
declare -r ERRLOG=${ROOT_DIR}scheduler.error_log
declare -r MATLAB_OUT=${ROOT_DIR}matlab.output
declare -a RESTRICTED_MACHINES=( "lapis" "aluminium" "argon" "arsenic" "beryllium" "boron" "bromine" "calcium" "carbon" "chlorine" "chromium" "cobalt" "copper" "fluorine" "gallium" "germanium" "helium" "hydrogen" "iron" "krypton" "lithium" "magnesium" "manganese" "neon" "nickel" "niobium" "nitrogen" "oxygen" "phosphorus" "potassium" "rubidium" "scandium" "selenium" "silicon" "sodium" "strontium" "sulfur" "titanium" "vanadium" "yttrium" "zirconium" "zinc" )
declare -r PROCESS_COMMAND="matlab -nodisplay -nodesktop -logfile $MATLAB_OUT -r 'setup_env(); j = Job(); j.get_and_run(); exit;'"
declare -r TMUX_WINDOW_NAME='scheduler'
declare -r RAM_LIMIT=90
declare -r UPPER_RAM_LIMIT=98

function is_running {
	if (( $(pgrep -c -u $USER -f scheduler.sh) > 1 )) ; then
		log 'already running'
		exit 1
	fi
	log 'starting : no instance found'
}

function clean_up_exit {
	local exit_code=$?
	log "Stopped with exit code : $exit_code"
}

function log {
	echo "[$(date)] : log : scheduler : $1 " | tee -a "$LOGFILE"
}

function error_log {
	echo "[$(date)] : ERR : scheduler : $1 " | tee -a "$ERRLOG"
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
		error_log 'Errors found, exiting'
		exit
	fi

	# # check to make sure we can access the servers we can connect too
	# ssh -q $MRS_REMOTE_HOST exit
	# if (( $? != 0 )) ; then
	# 	error_log 'cannot open ssh connection to tourmalet, but can ping : setup keys'
	# 	exit
	# fi

	# assumed that if you reach here, you can access the servers

	# some machines do not have matlab in the /usr/local/bin path so we need to add it to our $PATH

	# setup_matlab_path

	# make sure all the programs we need are installed!
	if ! type tmux >/dev/null 2>/dev/null; then
  		error_log "tmux is not installed"
  		exit
	elif ! type matlab >/dev/null 2>/dev/null; then
  		error_log "matlab is not installed"
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
	mkdir -p $MRS_LOCAL_DIR
	chmod 700 $ROOT_DIR
	mkdir -p $CONTROL_DIR
	log "setup directories : $MRS_LOCAL_DIR & $ROOT_DIR"
}

function email_stop {
	# switch possible mail clients : check return codes
	# there is no universal way to make this work, so instead of attaching the files : we just make them the body of the email..
	mail -s "Process stopped on machine $HOSTNAME : Scheduler log" chandlerm1@cs.cf.ac.uk < $LOGFILE
	mail -s "Process stopped on machine $HOSTNAME : Scheduler error log" chandlerm1@cs.cf.ac.uk < $ERRLOG
	mail -s "Process stopped on machine $HOSTNAME : Matlab log " chandlerm1@cs.cf.ac.uk < $MATLAB_OUT # as we've swapped to the internal matlab logging, it will append all of the info to this
}

# function setup_matlab_path {
# 	MATLAB_ROOT=$(locate /bin/matlab | grep matlab$);
# 	MATLAB_ROOT=${MATLAB_ROOT%matlab};
# 	if echo $PATH | grep -q $MATLAB_ROOT; then
#         log "Matlab root already in PATH";
# 	else
#         export PATH=$PATH:$MATLAB_ROOT >> /home/$USER/.profile;
#         log "Matlab root added to PATH";
# 	fi
# }

function update_repository {
	if ! tmux list-windows | grep "$TMUX_WINDOW_NAME">/dev/null; then
		if ! pgrep -x "rsync" -u $USER > /dev/null; then
			log "updating code repository : $CONTROL_DIR"
			if ping -c 1 -w 3 tourmalet.cs.cf.ac.uk &>/dev/null ; then
				log "rsyncing with : tourmalet"
				if is_restricted_machine ; then 
					log 'restricted  machine : nice and ionice used to rsync'
					nice -n 19 ionice -c2 -n7 rsync -r --delete --force $MRS_REMOTE_HOST:~/control/ $CONTROL_DIR
				else
					rsync -r --delete --force $MRS_REMOTE_HOST:~/control/ $CONTROL_DIR
				fi
			else
				error_log 'Cannot contact tourmalet to update repository'
			fi
			# if ping -c 1 -w 3 qyber.black &>/dev/null ; then
			# 	if git rev-parse $CONTROL_DIR > /dev/null 2>&1; then
			# 		git -C $CONTROL_DIR pull
			# 	else
			# 		git -C $CONTROL_DIR clone git@qyber.black:MRIS/control.git
			# 	fi
			# else
			# 	error_log 'Cannot contact qyber to update repository'
			# fi
		fi
		log 'code updated successfully'
	else
		log "\"$TMUX_WINDOW_NAME\" tmux window is open : not updating code"
	fi
}

function pause_matlab {
	kill -s SIGSTOP $(pgrep -u $USER MATLAB)
	log 'matlab paused'
}

function resume_matlab {
	PIDS=$(pgrep -u $USER MATLAB)
	for PID in $PIDS; do
		if [ "$(ps -o state= -p $PID)" = T ] ; then
			kill -SIGCONT $PID
			log 'matlab resumed'
		fi
	done
	
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
	email_stop
	exit
}

function start_processes {
	update_repository
	if ! tmux ls >/dev/null; then
		tmux new-session -d
		log "starting tmux session"
	fi

	if ! tmux list-windows | grep "$TMUX_WINDOW_NAME">/dev/null; then
		log "no \"$TMUX_WINDOW_NAME\" window found"
		if ! tmux list-windows | grep "$TMUX_WINDOW_NAME">/dev/null; then
			log "starting tmux window \"$TMUX_WINDOW_NAME\""
			tmux new-window -n "$TMUX_WINDOW_NAME"
		fi
		log 'MATLAB & tmux now running : starting job'
		if is_restricted_machine ; then
			log "Restricted machine : running job with nice -n 19 & ionice -c 2 -n 7 : $PROCESS_COMMAND"
			tmux send-keys -t "$TMUX_WINDOW_NAME" "cd $CONTROL_DIR/QControl/; nice -n 19 ionice -c2 -n7 $PROCESS_COMMAND" C-m
		else
			log "Unrestricted machine : running job : $PROCESS_COMMAND"
			tmux send-keys -t "$TMUX_WINDOW_NAME" "cd $CONTROL_DIR/QControl/; $PROCESS_COMMAND" C-m
		fi
	else
		log "\"$TMUX_WINDOW_NAME\" tmux window is open : not starting another job"
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
	return 0
	# for machine in ${RESTRICTED_MACHINES[@]} ; do
	# 	if [[ "$machine" == "$HOSTNAME" ]]; then
	# 		return 0
	# 	fi
	# done
	# return 1
}

function relax {
    num_users=$( who | sort --key=1,1 --unique | wc --lines )
    if (( $num_users > 1 )); then
        log 'More than one user'
  #       if lun -v >/dev/null ; then
  #           log 'Lun installed'
  #           if $(lun | grep -q -i 'bsc') || $(lun | grep -q -i 'masters') || $(lun | grep -q -i 'staff'); then
		# 		log 'relaxing'
		# 		return 0
  #           fi
		# else
			log 'relaxing'
		    return 0
		# fi
    fi
    # log 'no need to relax'
    return 1
}

function main {
	is_running
	clear_log
	check
	while true ; do
		if [[ $( free -m | awk 'NR==2{printf "%.f", $3*100/$2 }') > $RAM_LIMIT ]] ; then
			log "memory usage is higher than $RAM_LIMIT percent, killng process"
			kill_processes
			sleep 45m
		else
			start_processes
			if is_restricted_machine ; then
				# log "Running on a machine that is restricted in computing time & resources"
				# local H=$(date +%H)
				# if (( 8 <= 10#$H && 10#$H < 18 )); then 
				# 	log 'between 8AM and 6PM'
				if relax ; then
					pause_matlab
					# if memory usage is high when more than one user is on the machine, kill the process
					if [[ $( free -m | awk 'NR==2{printf "%.f", $3*100/$2 }') > $RAM_LIMIT ]] ; then
						log "memory usage is higher than $RAM_LIMIT percent, killng process"
						kill_processes
					fi
				else
					resume_matlab
				fi
				# else
				# 	log 'between 8AM and 6PM'
				# fi
			else
				# if [[ $( free -m | awk 'NR==2{printf "%.f", $3*100/$2 }') > $UPPER_RAM_LIMIT ]] ; then
				# 	log "memory usage is higher than $UPPER_RAM_LIMIT percent, killng process"
				# 	kill_processes
				# fi
				log "Unrestricted machine : attempting to start process"
			fi
		fi
		sleep $(( ( RANDOM % 15 )  + 10 ))
		has_finished
	done
}

trap clean_up_exit EXIT
main "$@"
