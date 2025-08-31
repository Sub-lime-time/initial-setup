# Common helper functions for setup scripts
# Provides apt_retry with lock-aware retries and safe messaging fallbacks.

# Fallback message helpers: if the main script defines warn/log/error, use them.
_msg_warn() {
    if declare -f warn >/dev/null 2>&1; then
        warn "$@"
    else
        echo "[WARN] $*" >&2
    fi
}
_msg_error() {
    if declare -f error >/dev/null 2>&1; then
        error "$@"
    else
        echo "[ERROR] $*" >&2
        exit 1
    fi
}

# Run apt-related commands with retries to handle dpkg/apt locks (e.g., unattended-upgrades).
# Usage: apt_retry <full-command...>
apt_retry() {
    local RETRY_INTERVAL=30
    local MAX_ATTEMPTS=0  # 0 means infinite - keep trying until it's available
    local attempt=0
    local cmd=("$@")

    while true; do
        attempt=$((attempt + 1))
        if "${cmd[@]}"; then
            return 0
        fi

        # Detect locks using lsof if available, otherwise check lock files exist
        if command -v lsof &>/dev/null && lsof /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock &>/dev/null; then
            _msg_warn "apt/dpkg appears locked. Attempt $attempt. Waiting ${RETRY_INTERVAL}s before retrying..."
            sleep "$RETRY_INTERVAL"
            if [ "$MAX_ATTEMPTS" -ne 0 ] && [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
                _msg_error "apt_retry: reached max attempts ($MAX_ATTEMPTS) while waiting for lock."
            fi
            continue
        elif [ -e /var/lib/dpkg/lock-frontend ] || [ -e /var/lib/dpkg/lock ] || [ -e /var/lib/apt/lists/lock ]; then
            _msg_warn "apt/dpkg lock files present. Attempt $attempt. Waiting ${RETRY_INTERVAL}s before retrying..."
            sleep "$RETRY_INTERVAL"
            if [ "$MAX_ATTEMPTS" -ne 0 ] && [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
                _msg_error "apt_retry: reached max attempts ($MAX_ATTEMPTS) while waiting for lock."
            fi
            continue
        else
            # Not a lock issue; propagate error
            return 1
        fi
    done
}
