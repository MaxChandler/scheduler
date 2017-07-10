#!/bin/bash

tmux kill-server
kill -s SIGKILL $(pgrep -u $USER -f scheduler_handler.sh)
kill -s SIGKILL $(pgrep -u $USER -f scheduler.sh)
kill -s SIGKILL $(pgrep -u $USER MATLAB)