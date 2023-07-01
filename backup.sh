#!/bin/bash


# NOTE: the exit code of this script is meaningless

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

source "$SCRIPT_DIR/config.sh"
export RESTIC_PASSWORD="$PASSWORD"
REPOSITORY="$(realpath --relative-to "$SCRIPT_DIR" "$REPOSITORY")"




# ---- UTILS ----

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
    # define handler for when cleanup fails
    # note that it is not possible trap EXIT inside of exit handler
    err_handler () {
        echo "ERROR: backup environment cleanup failed"
        send_error "backup environment cleanup failed"
        exit 1
    }
    trap err_handler ERR

    echo ""
    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval==255)); then
            echo "ERROR: error occurred or received exit signal"
            send_error "error occurred or received exit signal"
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

    cleanup
    exit $retval
}

cleanup () {
    echo "removing temporary backup environment"
    if [[ ${MOUNT_PID+1} ]]; then
        rm -d "$MOUNT_PATH"
        rm -d "$ROOT/$SOURCE_NAME"
        rm -rf "$ROOT"
    fi
}

trap exit_handler EXIT




# construct fake restic root dir
echo "creating temporary backup environment"
ROOT="$(mktemp -d)"
mkdir "$ROOT"/{tmp,repository,"$SOURCE_NAME"}

# copy restic executable
restic_path="$(which restic)" && true
if (($?>0)); then echo "ERROR: could not locate restic"; exit 1; fi
cp "$(realpath "$restic_path")" "$ROOT/restic"


# construct and run the backup command
cmd_1=(/restic -r /repository backup --ignore-inode /"$SOURCE_NAME")
cmd_2=(unshare -rR "$ROOT" "${cmd_1[@]}")
cmd_3=("$SCRIPT_DIR/serve-rclone-mount.sh" "$SOURCE" --mountpoint "$ROOT/$SOURCE_NAME" -- "${cmd_2[@]}")
cmd_4=("$SCRIPT_DIR/serve-bindfs-mount.sh" "$REPOSITORY" --mountpoint "$ROOT/repository" -- "${cmd_3[@]}")

echo ""
IS_LAUNCHED=1
"${cmd_4[@]}" && true
exit $?
