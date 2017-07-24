#!/bin/bash
declare -r TMUX_WINDOW_NAME='scheduler_handler'

if !(( $(pgrep -c -u $USER -f scheduler_handler.sh) > 1 )) ; then
	if ! tmux ls > /dev/null 2>&1 ; then
		# start new tmux session
		tmux start-server
		tmux new-session -d 
	fi
	if ! tmux list-windows | grep "$TMUX_WINDOW_NAME">/dev/null; then
		tmux new-window -n "$TMUX_WINDOW_NAME"
	fi
	tmux send-keys -t "$TMUX_WINDOW_NAME" "/home/$USER/scripts/scheduler_handler.sh" C-m
fi