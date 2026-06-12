#!/bin/bash
# Outputs clone URLs (one per line) for all repos belonging to a GitHub org or user.
# Usage: github-repos.sh <org-or-username>
# Respects GITHUB_SKIP_FORKS (default: true) and GITHUB_SKIP_ARCHIVED (default: false).
set -euo pipefail

: "${GITHUB_SKIP_FORKS:=true}"
: "${GITHUB_SKIP_ARCHIVED:=false}"

source="$1"
skip_forks=$( [[ "${GITHUB_SKIP_FORKS,,}" == "true" ]] && echo "true" || echo "false" )
skip_archived=$( [[ "${GITHUB_SKIP_ARCHIVED,,}" == "true" ]] && echo "true" || echo "false" )

page=1
while true; do
    response=$(curl -fsS --max-time 30 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/users/${source}/repos?per_page=100&page=${page}") || {
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] ERROR: GitHub API request failed for ${source} (page ${page})" >&2
        exit 1
    }

    count=$(echo "$response" | jq 'length')
    [[ "$count" -eq 0 ]] && break

    echo "$response" | jq -r \
        --argjson skip_forks "$skip_forks" \
        --argjson skip_archived "$skip_archived" \
        '.[] | select(if $skip_forks then .fork == false else true end)
             | select(if $skip_archived then .archived == false else true end)
             | .clone_url'

    page=$((page + 1))
done
