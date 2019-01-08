#!/bin/bash
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
SCRIPTNAME="$0"

declare -r TMUX_SESSION_NAME='scheduler'
declare -r TMUX_WINDOW_NAME='control'
declare -r PROGNAME=$(basename "$0")
declare -r ROOT_DIR=/tmp/${USER}/scheduler/
declare -r CODE_DIR=${ROOT_DIR}/code/
declare -r LOCK_FD=200

check(){
    # this stops errors when the machines become disconnected from the fileserver which is mounted on /home/$USER on some machines
    if [ ! -d "/home/${USER}/" ]; then
        exit 0
    fi
    # if the machine cannot connect to the internet, there's no point running this script as the repos cannot update
    ping -c1 google.com &>/dev/null
    if [ $? -eq 2 ]; then
        exit 0
    fi 
    
    # check the databse server
    ping -c1 ventoux.cs.cf.ac.uk &>/dev/null
    if [ $? -eq 2 ]; then
        exit 0
    fi 

    if ! type tmux >/dev/null 2>/dev/null; then
        error_log "tmux is not installed"
        exit
    fi
}

lock() {
    local prefix=$1
    local fd=${2:-$LOCK_FD}
    local lock_file="${ROOT_DIR}/${prefix}.lock"

    mkdir -p $ROOT_DIR &>/dev/null
    chmod 700 $ROOT_DIR &>/dev/null

    # create lock file
    eval "exec $fd>$lock_file"

    # acquier the lock
    flock -n $fd \
        && return 0 \
        || return 1
}

unlock() {
    local prefix=$1
    local fd=${2:-$LOCK_FD}
    local lock_file="${ROOT_DIR}/${prefix}.lock"

    flock --unlock $fd \
        && return 0 \
        || return 1
}

self_update() {
    # this comment is to test the update funciton 
    cd $SCRIPTPATH
    git fetch
    changed=1;
    git remote update &> /dev/null && git status -uno | grep -q "Your branch is behind"; changed=$?;

    if [ $changed == 0 ]; then 
        # don't forget that bash is reverse, 0 == true/OK, 1 = false.
        echo "Found a new version of me, updating myself..."
        git pull --force &>/dev/null
        git checkout &>/dev/null
        git pull --force &>/dev/null
        echo "Updated : running the new version of scheduler"
        unlock
        exec $SCRIPTNAME
        # Now exit this old instance
        exit 1
    fi
}

# clean_up_exit () {
#     local exit_code=$?
#     if [[ $exit_code != 0 ]]; then
#         echo "Stopped with exit code : $exit_code"
#     fi
#     unlock
# }

main () {
	check
    lock $PROGNAME || exit 0
    rm -rf $CODE_DIR # a fresh start!
    self_update
	cd ~/scheduler
	if ! tmux ls > /dev/null 2>&1 ; then
		tmux new-session -d -s $TMUX_SESSION_NAME -n $TMUX_WINDOW_NAME
        sleep 3s
	else
		if ! tmux list-sessions | grep -q $TMUX_SESSION_NAME; then
			tmux new-session -d -s $TMUX_SESSION_NAME
            sleep 3s
			if ! tmux list-windows | grep -q $TMUX_WINDOW_NAME; then
				tmux new-window -n $TMUX_WINDOW_NAME
                sleep 3s
			fi
		fi
	fi
    sleep 3s
	tmux send-keys -t $TMUX_WINDOW_NAME "./scheduler.sh" C-m
}

# trap clean_up_exit EXIT

main