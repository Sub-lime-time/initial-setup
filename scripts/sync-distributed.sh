#!/bin/bash
set -euo pipefail

# sync-distributed.sh
#
# This script synchronizes:
# 1. Scripts from /mnt/linux/distributed/scripts to /usr/local/bin
# 2. Cron jobs from /mnt/linux/distributed/cron.d to /etc/cron.d
# Cron files are only copied, with no deletion, to prevent accidental loss.
#
# Usage: Run the script as a user with appropriate permissions.

# Variables
SCRIPT_SOURCE_DIR="/mnt/linux/distributed/scripts"
SCRIPT_TARGET_DIR="/usr/local/bin"
CRON_SOURCE_DIR="/mnt/linux/distributed/cron.d"
CRON_TARGET_DIR="/etc/cron.d"
LOG_FILE="/var/log/sync-distributed.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
#RSYNC_OPTS="-av --chmod=+x"
RSYNC_OPTS="-a --no-perms --chmod=F744,D755"
SYSLOG_TAG="sync-distributed"

# Logging function (logs to syslog and optionally to a file)
log_message() {
    local MESSAGE="$1"
    logger -t "$SYSLOG_TAG" "$MESSAGE"
    echo "$MESSAGE"
    # Uncomment the next line to also log to a file:
    # echo "$TIMESTAMP $MESSAGE" >> "$LOG_FILE"
}

# Ensure source and target directories exist
check_directory() {
    local DIR="$1"
    local TYPE="$2"
    if [[ ! -d "$DIR" ]]; then
        log_message "ERROR: $TYPE directory $DIR does not exist. Exiting."
        exit 1
    fi
}

# Synchronization function using rsync
sync_directory() {
    local SOURCE="$1"
    local TARGET="$2"
    local DESC="$3"
    local EXTRA_OPTS="${4:-}"

    log_message "Starting synchronization for $DESC from $SOURCE to $TARGET."

    rsync $RSYNC_OPTS $EXTRA_OPTS "$SOURCE/" "$TARGET/"
    if [[ $? -eq 0 ]]; then
        log_message "Synchronization completed for $DESC."

        # Fix permissions for existing files and directories
        log_message "Fixing permissions for existing files in $TARGET."
        find "$TARGET" -type f -exec chmod 744 {} \;
        find "$TARGET" -type d -exec chmod 755 {} \;
        log_message "Permissions fixed for $DESC."
    else
        log_message "ERROR: Synchronization failed for $DESC."
        return 1
    fi
}

# Copy cron files without deletion
copy_cron_files() {
    log_message "Starting copy of cron files from $CRON_SOURCE_DIR to $CRON_TARGET_DIR."

    for FILE in "$CRON_SOURCE_DIR"/*; do
        if [[ -f "$FILE" ]]; then
            local BASENAME
            BASENAME=$(basename "$FILE")
            local TARGET_FILE="$CRON_TARGET_DIR/$BASENAME"

            # Check if the file is new or newer
            if [[ ! -f "$TARGET_FILE" ]] || [[ "$FILE" -nt "$TARGET_FILE" ]]; then
                cp "$FILE" "$TARGET_FILE"
                if [[ $? -eq 0 ]]; then
                    log_message "Copied cron file: $BASENAME"
                else
                    log_message "ERROR: Failed to copy cron file: $BASENAME"
                fi
            else
                log_message "No update needed for cron file: $BASENAME"
            fi
        else
            log_message "Skipping non-regular file in cron source: $(basename "$FILE")"
        fi
    done

    log_message "Cron file copy completed."
}

# Check required directories
check_directory "$SCRIPT_SOURCE_DIR" "Script source"
check_directory "$SCRIPT_TARGET_DIR" "Script target"
check_directory "$CRON_SOURCE_DIR" "Cron source"
check_directory "$CRON_TARGET_DIR" "Cron target"

# Synchronize scripts
# To mirror exactly (including deletions), add --delete to RSYNC_OPTS for scripts only:
# sync_directory "$SCRIPT_SOURCE_DIR" "$SCRIPT_TARGET_DIR" "scripts" "--delete"
sync_directory "$SCRIPT_SOURCE_DIR" "$SCRIPT_TARGET_DIR" "scripts"

# Copy cron files
copy_cron_files

# Completion
log_message "All synchronization tasks completed successfully."
exit 0
