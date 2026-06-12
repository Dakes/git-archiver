#!/bin/bash
# Syncs all repos for a single GitHub org or user: clones missing ones, pulls existing.
# Usage: github-sync.sh <org-or-username>
# Exit 0 = all succeeded. Exit 1 = one or more failures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

: "${GITHUB_SKIP_FORKS:=true}"
: "${GITHUB_SKIP_ARCHIVED:=false}"

source="$1"
target_dir="${REPOS_DIR}/${source}"

log "GITHUB: fetching repo list for ${source}"
repos_output=$("${SCRIPT_DIR}/github-repos.sh" "$source") || exit 1

if [[ -z "$repos_output" ]]; then
    log "GITHUB: no repos found for ${source}"
    exit 0
fi

mkdir -p "$target_dir"

failures=0
while IFS= read -r clone_url; do
    [[ -z "$clone_url" ]] && continue
    repo_name=$(basename "$clone_url" .git)

    if is_ignored "$repo_name"; then
        log "IGNORED: ${source}/${repo_name}"
        continue
    fi

    repo_path="${target_dir}/${repo_name}"
    if [[ ! -d "$repo_path" ]]; then
        log "CLONE: ${source}/${repo_name} (${clone_url})"
        if timeout "$GIT_TIMEOUT" git clone "$clone_url" "$repo_path"; then
            log "OK: ${source}/${repo_name} cloned"
        else
            log "ERROR: ${source}/${repo_name} clone failed"
            send_uptime_kuma_ping "down" "clone failed for ${source}/${repo_name}"
            failures=$((failures + 1))
        fi
    else
        "${SCRIPT_DIR}/process-repo.sh" "$repo_path" || failures=$((failures + 1))
    fi
done <<< "$repos_output"

[[ $failures -gt 0 ]] && exit 1
exit 0
