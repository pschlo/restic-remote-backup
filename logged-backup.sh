#!/bin/bash

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"


{
    echo ""
    echo ""
    echo ""
    "$SCRIPT_DIR/backup.sh" 2>&1 | "$SCRIPT_DIR/add-time.sh"
} | tee -ai "$SCRIPT_DIR/log.txt"
