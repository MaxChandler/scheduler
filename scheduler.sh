#!/bin/bash
declare -r ROOT_DIR=/tmp/${USER}/scheduler/code/
declare -r CONTROL_DIR=${ROOT_DIR}/control/
declare -r LOGFILE=${ROOT_DIR}scheduler.log
declare -r ERRLOG=${ROOT_DIR}scheduler.error_log
declare -r MATLAB_OUT=${ROOT_DIR}matlab.output
declare -r TMUX_SESSION_NAME='scheduler'
declare -r RAM_LIMIT=90
declare -r GIT_URL='git@github.com:MaxChandler/control.git'
declare -r MATLAB_COMMAND='try; setup_env(); j=Job(); j.get_and_run(); exit; catch err; exit; end;'

declare PAUSED=0
declare WINDOW_COUNT=0
declare MAX_NUM_PROCS=0
declare IDLE_CPU_LIM=0
declare CORES_PER_PROCESS=4

main () {
	is_running
	clear_log
	check
	setup
	while true ; do
		spawn_process
		while relax ; do  # there's another user on the system
			pause_processes
			if check_load ; then
				log "memory usage is higher than ${RAM_LIMIT} percent and there is another user on this machine: killng processes"
				kill_processes
			fi
			sleep 10s
		done
		resume_processes # allow the processes to spawn back up after being resumed before being killed instantly.
		check_processes # check to see if any processes have stalled
	done
}

is_running () {
	if (( $(pgrep -c -u $USER -f scheduler.sh) > 1 )) ; then
		exit 1
	fi
}

check_load () {
	if (( $( free -m | awk 'NR==2{printf "%.f", $3*100/$2 }') > $RAM_LIMIT )) ; then
		return 0
	fi
    return 1
}

check () {
    # if the machine cannot connect to the internet, there's no point running this script as the repos cannot update
    ping -c1 google.com &>/dev/null
    if [ $? -eq 2 ]; then
        error_log "Machine is not connected to the internet, stopping scheduler as a connection is required to update repositories."
        exit 0
    fi 

    # check the databse server
    ping -c1 ventoux.cs.cf.ac.uk &>/dev/null
    if [ $? -eq 2 ]; then
        error_log "Cannot reach the database server ventoux.cs.cf.ac.uk, but I can reach 'Google.com'. Exiting. "
        exit 0
    fi 

	# consistency checks : if there are pre-existing errors, then stop running
	if [ -f $ERRLOG ]; then
		error_log "Errors found, exiting"
		exit
	fi

	# make sure all the programs we need are installed!
	# could probably turn this into a loop...
	if ! type tmux >/dev/null 2>/dev/null; then
  		error_log "tmux is not installed"
  		exit
	fi

	if ! type matlab >/dev/null 2>/dev/null; then
  		error_log "matlab is not installed"
  		exit
	fi
	
}

setup () {
	set_num_cores
	set_max_num_procs
	setup_directories
}

set_num_cores () {
	n_cores=$(awk -F: '/^physical/ && !ID[$2] { P++; ID[$2]=1 }; /^cpu cores/ { CORES=$2 };  END { print CORES*P }' /proc/cpuinfo)
	log "${n_cores} physical cpu cores found"
}

set_max_num_procs (){
	MAX_NUM_PROCS=$(($n_cores/$CORES_PER_PROCESS))
	if [[ $MAX_NUM_PROCS == 0 ]]; then
		MAX_NUM_PROCS=1
	fi 
	log "${MAX_NUM_PROCS} processes can be run on this machine"
}

num_processes () {
	n_procs="$(tmux list-windows | grep -c runner*)"
}

spawn_process () {
	if [[ $PAUSED == 0 ]]; then
		num_processes
		while (( "$n_procs" < "$MAX_NUM_PROCS" )) ; do
			log "space for more processes : $n_procs processes running on $n_cores cores: spawning one more"
			start_process
			sleep 5s
			num_processes
		done
	fi
}

check_processes () {
	pane_pids=( $(tmux list-windows -t $TMUX_SESSION_NAME -F "#{window_name} #{pane_pid}" | grep -v "control" | awk '{print $2}') )
	if [[ $PAUSED == 0 ]]; then
		for pane_pid in $pane_pids; do
			child_pid=$(pgrep -P $pane_pid)
			if [ $? -eq 1 ]; then
				log "tmux pane has no child process associated with it (process must have finished and exited) : closing tmux pane."	
				tmux kill-window -t $(tmux list-windows -t $TMUX_SESSION_NAME -F "#{window_name} #{pane_pid}" | grep $pane_pid | awk '{print $1}')
			fi
			# this section is to check the CPU usage of the child processes incase they get stuck, it's not used at the moment
			# else
			# # log "found a child process : checking if it is OK"
			# cpu_usage=$(top -bn2 -d10 -p $child_pid | grep "Cpu(s)" | tail -n 1 | awk '{print int($2 + $4 + 0.5)}')
			# # if (( "$cpu_usage" < "$IDLE_CPU_LIM" )); then
			# # 	log "looks like process has stalled : cpu usage is less than $IDLE_CPU_LIM% : $cpu_usage"
			# # 	log "killing tmux-window $( tmux list-windows -t $TMUX_SESSION_NAME -F "#{window_name} #{pane_pid}" | grep $pane_pid | awk '{print $1'})"
			# # 	tmux kill-window -t $( tmux list-windows -t $TMUX_SESSION_NAME -F "#{window_name} #{pane_pid}" | grep $pane_pid | awk '{print $1'})
			# # 	email_stop
			# # else
			# # 	log "looks ok - leave it as is : cpu usage is $cpu_usage"
			# # fi
		done
	fi
}

pause_processes () {
	if (( $PAUSED==0 )); then 
		PAUSED=1
		log 'More than one user : relaxing processes'
		kill -s SIGSTOP $(pgrep -u $USER MATLAB)
		log "processes paused"
	fi
}

resume_processes () {
	if (( $PAUSED==1 )); then
		PAUSED=0
		PIDS=$(pgrep -u $USER MATLAB)
		for PID in $PIDS; do
			if [ "$(ps -o state= -p $PID)" = T ] ; then
				kill -SIGCONT $PID
			fi
		done
		log "matlab resumed"
		pause 5s
	fi
}

stop_processes () {
	if pgrep -u $USER "MATLAB" > /dev/null ; then
		pkill -u $USER "MATLAB"
		log 'Killed MATLAB'
	fi
	if  tmux list-windows | grep "$TMUX_SESSION_NAME">/dev/null; then
		tmux kill-window -t $TMUX_SESSION_NAME
		log "killed tmux window $TMUX_SESSION_NAME"
	fi
}

kill_processes () {
	stop_processes
	email_stop
	exit
}

clean_up_exit () {
	local exit_code=$?
	log "Stopped with exit code : $exit_code"
	tmux kill-session -t $TMUX_SESSION_NAME
}

log () {
	echo "[$(date)] : log : scheduler : $1 " | tee -a "$LOGFILE"
}

warning_log () {
	log "WARNING : $1 "
}

error_log () {
	echo "[$(date)] : ERR : scheduler : $1 " | tee -a "$ERRLOG"
}

clear_log () {
	rm -f $LOGFILE
	log "cleared old log file"
}

setup_directories () {
	mkdir -p $CONTROL_DIR &> /dev/null
	chmod 700 $ROOT_DIR
	log "setup directory : $CONTROL_DIR"
}

email_stop () {
	# switch possible mail clients : check return codes
	# there is no universal way to make this work, so instead of attaching the files : we just make them the body of the email..
	mail -s "Process stopped on machine $HOSTNAME : Scheduler log" chandlerm1@cs.cf.ac.uk < $LOGFILE
	if [ -a $ERRLOG ]; then
		mail -s "Process stopped on machine $HOSTNAME : Scheduler error log" chandlerm1@cs.cf.ac.uk < $ERRLOG
	fi
	matlab_logs=$(ls ${MATLAB_OUT}*)
	for mat_log in $matlab_logs; do
		mail -s "Process stopped on machine $HOSTNAME : Matlab log " chandlerm1@cs.cf.ac.uk < $mat_log # as we've swapped to the internal matlab logging, it will append all of the info to this
		rm $mat_log
	done	

}

update_code () {
	if [ -d "$CONTROL_DIR" ]; then
		rm -rf "$CONTROL_DIR"
	fi 
	log "cloning code from $GIT_URL"
	ssh-agent bash -c "ssh-add /home/${USER}/.ssh/id_rsa &>/dev/null; git -C ${ROOT_DIR} clone --depth 1 --recursive $GIT_URL &>/dev/null;"
	
}

start_process () {
	update_code
	# then we send the keys to create the next session
	log "starting new tmux window : runner_${WINDOW_COUNT}"
	tmux new-window -d -t $TMUX_SESSION_NAME -n "runner_${WINDOW_COUNT}"
	# get new tmux window name and attach it to the logs | C-m == Enter
	tmux send-keys -t "runner_${WINDOW_COUNT}" "cd $CONTROL_DIR/QControl/; matlab -nodisplay -nodesktop -logfile ${MATLAB_OUT}_${WINDOW_COUNT} -r '${MATLAB_COMMAND}'; exit; exit "	C-m
	# update theh window count to give each window a unique ID 
	((WINDOW_COUNT++))
}

relax () {
    num_users=$( who | sort --key=1,1 --unique | wc --lines )
    if (( $num_users > 1 )); then
		return 0
    fi
    return 1
}

trap clean_up_exit EXIT
main "$@"