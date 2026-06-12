#!/bin/bash
# Validates and pulls a single git repository.
# Usage: process-repo.sh <repo-path>
# Exit 0 = success or intentional skip. Exit 1 = pull failed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

repo_path="$1"
repo_name=$(basename "$repo_path")

if is_ignored "$repo_name"; then
    log "IGNORED: ${repo_name}"
    exit 0
fi

if ! timeout "$GIT_TIMEOUT" git -C "$repo_path" rev-parse --git-dir > /dev/null 2>&1; then
    log "SKIP: ${repo_name} is not a valid git repository"
    exit 0
fi

if [[ "$(timeout "$GIT_TIMEOUT" git -C "$repo_path" config --get core.bare 2>/dev/null || echo false)" == "true" ]]; then
    log "SKIP: ${repo_name} is a bare repository"
    exit 0
fi

remote_url=$(timeout "$GIT_TIMEOUT" git -C "$repo_path" remote get-url origin 2>/dev/null || true)
if [[ -z "$remote_url" ]]; then
    log "SKIP: ${repo_name} has no origin remote"
    exit 0
fi

if ! timeout "$GIT_TIMEOUT" git -C "$repo_path" ls-remote origin > /dev/null 2>&1; then
    log "SKIP: ${repo_name} remote is not accessible (${remote_url})"
    exit 0
fi

log "PULL: ${repo_name} (${remote_url})"
if timeout "$GIT_TIMEOUT" git -C "$repo_path" pull --ff-only; then
    log "OK: ${repo_name} updated"
else
    log "ERROR: ${repo_name} git pull failed"
    send_uptime_kuma_ping "down" "git pull failed for ${repo_name}"
    exit 1
fi
