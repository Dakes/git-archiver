#!/bin/bash
# Shared utilities sourced by backup scripts. Not intended to be run directly.

: "${REPOS_DIR:=/repos}"
: "${UPTIME_KUMA_URL:=}"
: "${GIT_TIMEOUT:=300}"
: "${IGNORE_REPOS:=}"
: "${IGNORE_FILE:=}"

log() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"
}

is_ignored() {
    local repo_name="$1"

    if [[ -n "$IGNORE_REPOS" ]]; then
        local item cleaned
        IFS=',' read -ra ignored_arr <<< "$IGNORE_REPOS"
        for item in "${ignored_arr[@]}"; do
            cleaned="$(echo "$item" | tr -d '[:space:]')"
            [[ "$cleaned" == "$repo_name" ]] && return 0
        done
    fi

    local ignore_file_path="${IGNORE_FILE:-$REPOS_DIR/.git-backup-ignore}"
    if [[ -f "$ignore_file_path" ]]; then
        local line cleaned
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            cleaned="$(echo "$line" | tr -d '[:space:]')"
            [[ -n "$cleaned" && "$cleaned" == "$repo_name" ]] && return 0
        done < "$ignore_file_path"
    fi

    return 1
}

send_uptime_kuma_ping() {
    [[ -z "$UPTIME_KUMA_URL" ]] && return 0
    local status="$1" msg="$2"
    if curl -fsS --max-time 30 --get \
        --data-urlencode "status=${status}" \
        --data-urlencode "msg=${msg}" \
        "$UPTIME_KUMA_URL" > /dev/null 2>&1; then
        log "UPTIME_KUMA: sent ${status} ping"
    else
        log "WARN: Failed to send Uptime Kuma ${status} ping"
    fi
}
