#!/bin/bash
declare -r TMUX_WINDOW_NAME='scheduler_handler'

if !(( $(pgrep -c -u $USER -f scheduler_handler.sh) > 1 )) ; then
	if ! tmux ls > /dev/null 2>&1 ; then
		tmux start-server
		tmux new-session -d 
		# start new tmux session
		tmux new-window -n "$TMUX_WINDOW_NAME"
		tmux send-keys -t "$TMUX_WINDOW_NAME" "./home/$USER/scripts/scheduler_handler.sh" C-m
	fi
fi