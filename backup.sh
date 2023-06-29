#!/bin/bash


# NOTE: the exit code of this script is meaningless

set -o errexit
set -o nounset
set -o pipefail
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

cd "$SCRIPT_DIR"
source "./config.sh"
source "./mount-utils.sh"
export RESTIC_PASSWORD="$PASSWORD"




send_telegram () {
    echo -e "sending Telegram message"
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


exit_handler () {
    retval=$?
    set +o errexit
    echo ""

    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval==255)); then
            echo "ERROR: backup was not executed or exit signal has been received or cloud cleanup failed"
            send_error "backup was not executed or exit signal has been received or cloud cleanup failed"
        elif ((retval==0)); then
            echo "backup completed"
            send_succ "backup"
        else
            echo "ERROR: backup failed with code $retval"
            send_error "backup failed with code $retval"
        fi
    else
        if ((retval==0)); then
            # this means that exit 0 was called before the backup was started
            echo "finished without backing up"
            send_succ "finished without backing up"
        else
            echo "ERROR: backup was not started: an error occurred"
            send_error "backup was not started: an error occurred"
        fi
    fi

    cleanup || retval=1
    exit $retval
}


cleanup () {
    err () {
        echo "ERROR: backup environment cleanup failed"
        send_error "backup environment cleanup failed"
    }
    echo "removing temporary backup environment"
    {
        if [[ ${MOUNT_PID+1} ]]; then
            stop_mount $MOUNT_PID "$MOUNT_PATH" &&
            rm -d "$MOUNT_PATH" &&
            rm -d "$RESTIC_ROOT/$SOURCE_NAME" &&
            rm -rf "$RESTIC_ROOT"
        fi
    } || { err; return 1; }
    return 0
}

trap exit_handler EXIT




# construct fake restic root dir
echo "creating temporary backup environment"
RESTIC_ROOT="$(mktemp -d)"
mkdir "$RESTIC_ROOT"/{tmp,repository,"$SOURCE_NAME"}

# copy restic executable
RESTIC_PATH="$(which restic)" && true
if (($?>0)); then echo "ERROR: could not locate restic"; exit 1; fi
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

echo ""
IS_LAUNCHED=1
# ( exit 255 ) && true
"./serve-rclone-mount.sh" --mountpoint "$RESTIC_ROOT/$SOURCE_NAME" "$SOURCE" "${chrooted_command[@]}" && true
exit $?
