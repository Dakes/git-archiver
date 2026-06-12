#!/bin/bash
set -euo pipefail

shopt -s nullglob

: "${REPOS_DIR:=/repos}"
: "${UPTIME_KUMA_URL:=}"
: "${GIT_TIMEOUT:=300}"
: "${IGNORE_REPOS:=}"
: "${IGNORE_FILE:=}"
: "${REPO_GROUPS:=}"

log() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"
}

is_ignored() {
    local repo_name="$1"

    # 1. Comma-separated list from environment variable.
    if [[ -n "$IGNORE_REPOS" ]]; then
        local item
        local cleaned
        IFS=',' read -ra ignored_arr <<< "$IGNORE_REPOS"
        for item in "${ignored_arr[@]}"; do
            cleaned="$(echo "$item" | tr -d '[:space:]')"
            if [[ "$cleaned" == "$repo_name" ]]; then
                return 0
            fi
        done
    fi

    # 2. Ignore file (one repo name per line, # comments allowed).
    local ignore_file_path="${IGNORE_FILE:-$REPOS_DIR/.git-backup-ignore}"
    if [[ -f "$ignore_file_path" ]]; then
        local line
        local cleaned
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            cleaned="$(echo "$line" | tr -d '[:space:]')"
            if [[ -n "$cleaned" && "$cleaned" == "$repo_name" ]]; then
                return 0
            fi
        done < "$ignore_file_path"
    fi

    return 1
}

is_group() {
    local dir_name="$1"
    [[ -z "$REPO_GROUPS" ]] && return 1
    local item cleaned
    IFS=',' read -ra groups_arr <<< "$REPO_GROUPS"
    for item in "${groups_arr[@]}"; do
        cleaned="$(echo "$item" | tr -d '[:space:]')"
        [[ "$cleaned" == "$dir_name" ]] && return 0
    done
    return 1
}

urlencode_msg() {
    # Uptime Kuma expects query parameters; spaces become '+'.
    local msg="$1"
    echo "${msg// /+}"
}

send_uptime_kuma_ping() {
    if [[ -z "$UPTIME_KUMA_URL" ]]; then
        return 0
    fi

    local status="$1"
    local msg
    msg=$(urlencode_msg "$2")

    if curl -fsS --max-time 30 --get \
        --data-urlencode "status=${status}" \
        --data-urlencode "msg=${msg}" \
        "$UPTIME_KUMA_URL" > /dev/null 2>&1; then
        log "UPTIME_KUMA: sent ${status} ping (${msg})"
    else
        log "WARN: Failed to send Uptime Kuma ${status} ping"
    fi
}

process_repo() {
    local repo_path="$1"
    local repo_name
    repo_name=$(basename "$repo_path")

    if is_ignored "$repo_name"; then
        log "IGNORED: ${repo_name}"
        return 0
    fi

    # 1. Valid git repository?
    if ! timeout "$GIT_TIMEOUT" git -C "$repo_path" rev-parse --git-dir > /dev/null 2>&1; then
        log "SKIP: ${repo_name} is not a valid git repository"
        return 0
    fi

    # 2. Bare repository? We cannot pull those.
    if [[ "$(timeout "$GIT_TIMEOUT" git -C "$repo_path" config --get core.bare 2>/dev/null || echo false)" == "true" ]]; then
        log "SKIP: ${repo_name} is a bare repository"
        return 0
    fi

    # 3. Has an origin remote?
    local remote_url
    remote_url=$(timeout "$GIT_TIMEOUT" git -C "$repo_path" remote get-url origin 2>/dev/null || true)
    if [[ -z "$remote_url" ]]; then
        log "SKIP: ${repo_name} has no origin remote"
        return 0
    fi

    # 4. Remote accessible?
    if ! timeout "$GIT_TIMEOUT" git -C "$repo_path" ls-remote origin > /dev/null 2>&1; then
        log "SKIP: ${repo_name} remote is not accessible (${remote_url})"
        return 0
    fi

    # 5. Pull updates (fast-forward only to keep the mirror clean).
    log "PULL: ${repo_name} (${remote_url})"
    if timeout "$GIT_TIMEOUT" git -C "$repo_path" pull --ff-only; then
        log "OK: ${repo_name} updated"
    else
        log "ERROR: ${repo_name} git pull failed"
        send_uptime_kuma_ping "down" "git pull failed for ${repo_name}"
        return 1
    fi
}

main() {
    log "=== Starting git backup run ==="

    if [[ ! -d "$REPOS_DIR" ]]; then
        log "ERROR: Repos directory does not exist: ${REPOS_DIR}"
        send_uptime_kuma_ping "down" "repos directory missing"
        exit 1
    fi

    # Prevent overlapping runs.
    LOCK_FILE="/tmp/git-backup.lock"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "SKIP: Another backup run is already in progress"
        exit 0
    fi

    local failures=0
    local repo repo_name subrepo
    for repo in "${REPOS_DIR}"/*/; do
        [[ -d "$repo" ]] || continue
        repo_name=$(basename "$repo")
        if is_group "$repo_name"; then
            log "GROUP: ${repo_name}"
            for subrepo in "$repo"*/; do
                [[ -d "$subrepo" ]] && { process_repo "$subrepo" || failures=$((failures + 1)); }
            done
        else
            process_repo "$repo" || failures=$((failures + 1))
        fi
    done

    log "=== Finished git backup run (failures: ${failures}) ==="

    if [[ $failures -eq 0 ]]; then
        send_uptime_kuma_ping "up" "OK"
    fi
}

main "$@"
