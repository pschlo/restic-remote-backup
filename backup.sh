#!/bin/bash


# NOTE: the exit code of this script is meaningless

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

cd "$SCRIPT_DIR"
source "./config.sh"
source "./mount-utils.sh"
export RESTIC_PASSWORD="$PASSWORD"




send_telegram () {
    log -e "sending Telegram message"
    curl -X POST \
        --no-progress-meter \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": $CHAT_ID, \"text\": \"${1}\"}" \
        https://api.telegram.org/bot$BOT_TOKEN/sendMessage \
        >/dev/null
}

timestamp () {
    echo "$(date +"%Y-%m-%d %T")"
}

send_error () {
    send_telegram "❌ ${1}"
}

send_succ () {
    send_telegram "✅ ${1}"
}

# try to echo to stdout, or if that fails to stderr. If that fails too, do nothing.
# this is used to ensure the script does not crash if no output is connected and echo fails
log () {
    echo "$@" 2>/dev/null || echo "$@" 1>&2 || return 0
}
trap : PIPE



exit_handler () {
    retval=$?
    # define handler for when cleanup fails
    # note that it is not possible trap EXIT inside of exit handler
    err_handler () {
        log "ERROR: backup environment cleanup failed"
        send_error "backup environment cleanup failed"
        exit 1
    }
    trap err_handler ERR

    log ""
    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval==255)); then
            log "ERROR: error occurred or received exit signal"
            send_error "error occurred or received exit signal"
        elif ((retval==0)); then
            log "backup completed"
            send_succ "backup"
        else
            log "ERROR: backup failed with code $retval"
            send_error "backup failed with code $retval"
        fi
    else
        if ((retval==0)); then
            # this means that exit 0 was called before the backup was started
            log "finished without backing up"
            send_succ "finished without backing up"
        else
            log "ERROR: backup was not started: an error occurred"
            send_error "backup was not started: an error occurred"
        fi
    fi

    cleanup
    exit $retval
}

cleanup () {
    log "removing temporary backup environment"
    if [[ ${MOUNT_PID+1} ]]; then
        stop_mount $MOUNT_PID "$MOUNT_PATH"
        rm -d "$MOUNT_PATH"
        rm -d "$RESTIC_ROOT/$SOURCE_NAME"
        rm -rf "$RESTIC_ROOT"
    fi
}

trap exit_handler EXIT




# construct fake restic root dir
log "creating temporary backup environment"
RESTIC_ROOT="$(mktemp -d)"
mkdir "$RESTIC_ROOT"/{tmp,repository,"$SOURCE_NAME"}

# copy restic executable
RESTIC_PATH="$(which restic)" && true
if (($?>0)); then log "ERROR: could not locate restic"; exit 1; fi
cp "$(realpath "$RESTIC_PATH")" "$RESTIC_ROOT/restic"

# mount restic repository
# launch as daemon, but keep stdout connected to current terminal
MOUNT_PATH="$RESTIC_ROOT/repository"
setsid bindfs -f "$REPOSITORY" "$MOUNT_PATH" &
MOUNT_PID=$!

wait_mount $MOUNT_PID "$MOUNT_PATH"


# construct and run the backup command
restic_command=(./restic -r repository backup --ignore-inode /"$SOURCE_NAME")
chrooted_command=(unshare -rR "$RESTIC_ROOT" "${restic_command[@]}")

log ""
IS_LAUNCHED=1
"./serve-rclone-mount.sh" --mountpoint "$RESTIC_ROOT/$SOURCE_NAME" "$SOURCE" "${chrooted_command[@]}" && true
exit $?
