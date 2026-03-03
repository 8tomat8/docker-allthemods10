#!/usr/bin/env bash
set -euo pipefail

RCON_HOST="${RCON_HOST}"
RCON_PORT="${RCON_PORT}"
RCON_PASSWORD="${RCON_PASSWORD}"
RESTART_INTERVAL_HOURS="${RESTART_INTERVAL_HOURS}"
RESTART_WARNING_MINUTES="${RESTART_WARNING_MINUTES}"
RESTART_FINAL_COUNTDOWN_SECONDS=10
RESTART_GRACE_SECONDS=15
RESTART_MESSAGE_PREFIX="[Server]"

strip_wrapping_quotes() {
    local value="$1"
    if [[ ${#value} -ge 2 ]]; then
        if [[ "$value" == "\""*"\"" ]] || [[ "$value" == "'"*"'" ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi
    printf '%s' "$value"
}

RCON_HOST="$(strip_wrapping_quotes "$RCON_HOST")"
RCON_PORT="$(strip_wrapping_quotes "$RCON_PORT")"
RCON_PASSWORD="$(strip_wrapping_quotes "$RCON_PASSWORD")"
RESTART_INTERVAL_HOURS="$(strip_wrapping_quotes "$RESTART_INTERVAL_HOURS")"
RESTART_WARNING_MINUTES="$(strip_wrapping_quotes "$RESTART_WARNING_MINUTES")"

if [[ -z "$RCON_PASSWORD" ]]; then
    echo "RCON_PASSWORD is required for restart announcements."
    exit 1
fi

if ! [[ "$RCON_PORT" =~ ^[0-9]+$ ]] || ((RCON_PORT < 1 || RCON_PORT > 65535)); then
    echo "RCON_PORT must be a number between 1 and 65535."
    exit 1
fi

if ! [[ "$RESTART_INTERVAL_HOURS" =~ ^[0-9]+$ ]] || ((RESTART_INTERVAL_HOURS < 1)); then
    echo "RESTART_INTERVAL_HOURS must be a positive integer."
    exit 1
fi

rcon_run() {
    local cmd="$*"
    if command -v timeout >/dev/null 2>&1; then
        timeout 10s rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "$cmd"
    else
        rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "$cmd"
    fi
}

rcon_retry() {
    local cmd="$*"
    local attempts=0

    until rcon_run "$cmd" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [[ $attempts -ge 20 ]]; then
            echo "RCON command failed after retries: $cmd"
            return 1
        fi
        sleep 3
    done
    return 0
}

say() {
    local text="$*"
    rcon_retry "say $text" || true
}

wait_for_rcon() {
    echo "Waiting for RCON at ${RCON_HOST}:${RCON_PORT}..."
    rcon_retry "list"
}

announce_and_restart() {
    local last_minutes=0
    local minutes=0
    local tail_sleep=0
    local seconds=0
    local -a sorted_warnings=()

    IFS=',' read -r -a warnings <<< "$RESTART_WARNING_MINUTES"
    mapfile -t sorted_warnings < <(printf '%s\n' "${warnings[@]}" | tr -d '[:space:]' | awk '/^[0-9]+$/ && $1 > 0' | sort -rn)

    for minutes in "${sorted_warnings[@]}"; do

        if [[ "$last_minutes" -gt 0 ]]; then
            sleep $(((last_minutes - minutes) * 60))
        fi

        say "${RESTART_MESSAGE_PREFIX} Restart in ${minutes} minute(s)."
        last_minutes="$minutes"
    done

    if [[ "$last_minutes" -gt 0 ]]; then
        tail_sleep=$((last_minutes * 60 - RESTART_FINAL_COUNTDOWN_SECONDS))
        if [[ "$tail_sleep" -gt 0 ]]; then
            sleep "$tail_sleep"
        fi
    fi

    for ((seconds = RESTART_FINAL_COUNTDOWN_SECONDS; seconds >= 1; seconds--)); do
        say "${RESTART_MESSAGE_PREFIX} Restart in ${seconds}..."
        sleep 1
    done

    say "${RESTART_MESSAGE_PREFIX} Restarting now."
    rcon_retry "save-all" || true
    sleep 2
    rcon_retry "stop"
    sleep "$RESTART_GRACE_SECONDS"
}

until wait_for_rcon; do
    echo "RCON not ready yet; retrying in 15 seconds."
    sleep 15
done

while true; do
    sleep "$((RESTART_INTERVAL_HOURS * 3600))"
    if ! wait_for_rcon; then
        echo "RCON unavailable, skipping this restart cycle."
        continue
    fi
    if ! announce_and_restart; then
        echo "Restart cycle failed; continuing to next schedule."
    fi
done
