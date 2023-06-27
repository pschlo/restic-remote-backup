#!/bin/bash


# NOTE: the exit code of this script is meaningless

set -o errexit
set -o nounset
set -o pipefail
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

cd "$SCRIPT_DIR"
source "./config.sh"
export RESTIC_PASSWORD="$PASSWORD"


# for a received signal, this script should return the canonical code
# otherwise, sending e.g. SIGINT would make the script exit with code 0
# see https://www.gnu.org/software/libc/manual/html_node/Termination-Signals.html
# for numbers, see trap -l
for i in 15 2 3 9 1; do
    trap "exit $((128+$i))" $i
done




send_telegram () {
    echo -e "sending Telegram message"
    curl -X POST \
    --no-progress-meter \
    -H 'Content-Type: application/json' \
    -d "{\"chat_id\": $CHAT_ID, \"text\": \"${1}\"}" \
    https://api.telegram.org/bot$BOT_TOKEN/sendMessage
    echo -e "\n"
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

is_special_exit () {
    (($1>=126)) && (($1<=165))
}


exit_handler () {
    retval=$?
    set +o errexit
    echo ""
    echo ""

    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval==255)); then
            echo "ERROR: an internal error occurred"
            send_error "internal error"
        elif ((retval==0)); then
            echo "backup completed"
            send_succ "backup"
        else
            echo "ERROR: backup failed"
            send_error "backup failed"
        fi
    else
        if ((retval==0)); then
            # this means that exit 0 was called before the backup was started
            echo "finished without backing up"
            send_succ "finished without backing up"
        elif is_special_exit $retval; then
            echo "ERROR: shell error or exit signal"
            send_error "shell error or exit signal"
        else
            echo "ERROR: backup was not started: an error occurred"
            send_error "backup was not started: an error occurred"
        fi
    fi

    cleanup
}

cleanup_err () {
    echo "ERROR: cleanup unsuccessful"
    send_error "cleanup error"
    exit 10
}

# requires $retval
cleanup () {
    echo "deleting temporary backup environment"
    mountpoint -q "$RESTIC_ROOT/repository" && umount "$RESTIC_ROOT/repository"
    sleep 0.5
    rm -d "$RESTIC_ROOT/repository" || cleanup_err
    rm -r "$RESTIC_ROOT" || cleanup_err
    exit $retval
}

trap exit_handler EXIT




# construct fake restic root dir
echo "creating temporary backup environment"
RESTIC_ROOT="$(mktemp -d)"
mkdir "$RESTIC_ROOT"/{tmp,repository,"$SOURCE_NAME"}
RESTIC_PATH="$(which restic)" && true
if (($?>0)); then echo "ERROR: could not locate restic"; exit 1; fi
cp "$(realpath "$RESTIC_PATH")" "$RESTIC_ROOT/restic"
bindfs "$REPOSITORY" "$RESTIC_ROOT/repository"


# construct and run the backup command
restic_command=(./restic -r repository backup --ignore-inode "$SOURCE_NAME")
chrooted_command=(unshare -rR "$RESTIC_ROOT" "${restic_command[@]}")
mountpoint="$RESTIC_ROOT/$SOURCE_NAME"

IS_LAUNCHED=1
"./serve-rclone-mount.sh" --mountpoint "$mountpoint" "$SOURCE" "${chrooted_command[@]}" && true
exit $?
