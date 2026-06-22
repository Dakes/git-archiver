#!/bin/bash
set -euo pipefail

: "${REPOS_DIR:=/repos}"
: "${CRON_SCHEDULE:=30 4 * * 1}"
: "${UPTIME_KUMA_URL:=}"
: "${RUN_ON_STARTUP:=true}"
: "${PUID:=1000}"
: "${PGID:=1000}"
: "${IGNORE_REPOS:=}"
: "${IGNORE_FILE:=}"
: "${REPO_GROUPS:=}"
: "${GITHUB_SOURCES:=}"
: "${GITHUB_SKIP_FORKS:=true}"
: "${GITHUB_SKIP_ARCHIVED:=false}"

log() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] entrypoint: $*" >&2
}

# Basic cron validation: must contain exactly 5 fields.
if [[ "$(echo "$CRON_SCHEDULE" | awk '{print NF}')" -ne 5 ]]; then
    log "ERROR: CRON_SCHEDULE must contain exactly 5 fields (e.g. '30 4 * * 1')"
    exit 1
fi

# Create a runtime user matching the host UID/GID so git operations preserve
# file ownership on the bind-mounted volume.
if ! getent group "$PGID" > /dev/null 2>&1; then
    GROUP_NAME="appgroup"
    addgroup -g "$PGID" "$GROUP_NAME"
else
    GROUP_NAME=$(getent group "$PGID" | cut -d: -f1)
fi

if ! getent passwd "$PUID" > /dev/null 2>&1; then
    USER_NAME="appuser"
    adduser -u "$PUID" -G "$GROUP_NAME" -D -H "$USER_NAME"
else
    USER_NAME=$(getent passwd "$PUID" | cut -d: -f1)
fi

# Install the crontab under root so the redirect to /proc/1/fd/1 (owned by root/PID 1)
# succeeds. The job drops to the runtime user via `su` before running backup.sh,
# matching the same pattern used for the startup run below.
CRONTAB_FILE="/etc/crontabs/root"
{
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    echo "REPOS_DIR=${REPOS_DIR}"
    echo "UPTIME_KUMA_URL=${UPTIME_KUMA_URL}"
    echo "GIT_TIMEOUT=${GIT_TIMEOUT:-300}"
    echo "IGNORE_REPOS=${IGNORE_REPOS}"
    echo "IGNORE_FILE=${IGNORE_FILE}"
    echo "REPO_GROUPS=${REPO_GROUPS}"
    echo "GITHUB_SOURCES=${GITHUB_SOURCES}"
    echo "GITHUB_SKIP_FORKS=${GITHUB_SKIP_FORKS}"
    echo "GITHUB_SKIP_ARCHIVED=${GITHUB_SKIP_ARCHIVED}"
    echo "${CRON_SCHEDULE} su -s /bin/bash ${USER_NAME} -c '/usr/local/bin/backup.sh' >> /proc/1/fd/1 2>&1"
} > "$CRONTAB_FILE"
chmod 600 "$CRONTAB_FILE"

log "Installed crontab for user $USER_NAME ($PUID:$PGID): $CRON_SCHEDULE /usr/local/bin/backup.sh"

if [[ "$RUN_ON_STARTUP" == "true" ]]; then
    log "Running backup once at startup..."
    su -s /bin/bash "$USER_NAME" -c "/usr/local/bin/backup.sh"
fi

log "Starting cron daemon..."
exec crond -f -l 2
