#!/bin/bash
# Main orchestrator: iterates local repos/groups and GitHub sources.
set -euo pipefail

shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

: "${REPO_GROUPS:=}"
: "${GITHUB_SOURCES:=}"

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

is_github_source() {
    local dir_name="$1"
    [[ -z "$GITHUB_SOURCES" ]] && return 1
    local item cleaned
    IFS=',' read -ra sources_arr <<< "$GITHUB_SOURCES"
    for item in "${sources_arr[@]}"; do
        cleaned="$(echo "$item" | tr -d '[:space:]')"
        [[ "$cleaned" == "$dir_name" ]] && return 0
    done
    return 1
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

    local failures=0 repo repo_name subrepo

    # Local repos and manually-managed groups.
    for repo in "${REPOS_DIR}"/*/; do
        [[ -d "$repo" ]] || continue
        repo_name=$(basename "$repo")
        if is_github_source "$repo_name"; then
            continue  # managed by GitHub sync below
        elif is_group "$repo_name"; then
            log "GROUP: ${repo_name}"
            for subrepo in "$repo"*/; do
                [[ -d "$subrepo" ]] && { "${SCRIPT_DIR}/process-repo.sh" "$subrepo" || failures=$((failures + 1)); }
            done
        else
            "${SCRIPT_DIR}/process-repo.sh" "$repo" || failures=$((failures + 1))
        fi
    done

    # GitHub org/user sources.
    if [[ -n "$GITHUB_SOURCES" ]]; then
        local source cleaned
        IFS=',' read -ra sources_arr <<< "$GITHUB_SOURCES"
        for source in "${sources_arr[@]}"; do
            cleaned="$(echo "$source" | tr -d '[:space:]')"
            [[ -z "$cleaned" ]] && continue
            "${SCRIPT_DIR}/github-sync.sh" "$cleaned" || failures=$((failures + 1))
        done
    fi

    log "=== Finished git backup run (failures: ${failures}) ==="

    if [[ $failures -eq 0 ]]; then
        send_uptime_kuma_ping "up" "OK"
    fi
}

main "$@"
