#!/bin/bash

# this script adds a timestamp to lines from STDIN


# by default, the script should not terminate from signals
# otherwise, writing pipe end might receive SIGPIPE
for ((i=0; i<100; i++)); do
    trap : $i 2>/dev/null && true
done

# add timestamp to input
while IFS= read -r line; do
    echo "[$(date +"%Y-%m-%d %T")] $line"
done
