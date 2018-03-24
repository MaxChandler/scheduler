#!/bin/bash
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
SCRIPTNAME="$0"

declare -r TMUX_SESSION_NAME='scheduler'
declare -r TMUX_WINDOW_NAME='control'
readonly PROGNAME=$(basename "$0")
readonly LOCKFILE_DIR=/tmp/${USER}
readonly LOCK_FD=200

lock() {
    local prefix=$1
    local fd=${2:-$LOCK_FD}
    local lock_file=$LOCKFILE_DIR/$prefix.lock

    mkdir -p $LOCKFILE_DIR &>/dev/null
    chmod 700 $LOCKFILE_DIR &>/dev/null

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
    local lock_file=$LOCKFILE_DIR/$prefix.lock

    flock --unlock $fd \
        && return 0 \
        || return 1
}

self_update() {
    git fetch
    cd $SCRIPTPATH

    changed=0
    git -q remote update && git status -uno | grep -q 'Your branch is behind' && changed=1

    if [ $changed = 1 ]; then 
        echo "Found a new version of me, updating myself..."
        git pull --force
        git checkout 
        git pull --force
        echo "Running the new version..."
        unlock()
        exec "$SCRIPTNAME"
        # Now exit this old instance
        exit 1
    else
        echo "Already the latest version."
    fi
}

clean_up_exit () {
    local exit_code=$?
    echo "Stopped with exit code : $exit_code"
    unlock()
}

main () {
    mkdir -p $LOCKFILE_DIR
	lock $PROGNAME || exit 1
	self_update
	cd ~/scheduler
	if ! tmux ls > /dev/null 2>&1 ; then
		tmux new-session -d -s "$TMUX_SESSION_NAME" -n $TMUX_WINDOW_NAME
	else
		if ! tmux list-sessions | grep "$TMUX_SESSION_NAME">/dev/null; then
			tmux new-session -d -s "$TMUX_SESSION_NAME"
			if ! tmux list-windows | grep $TMUX_WINDOW_NAME>/dev/null; then
				tmux new-window -n $TMUX_WINDOW_NAME
			fi
		fi
	fi
	tmux send-keys -t $TMUX_WINDOW_NAME "./scheduler.sh" C-m
	tmux attach-session -t $TMUX_SESSION_NAME
}
trap clean_up_exit EXIT
main