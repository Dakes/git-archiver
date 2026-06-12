FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    tzdata && \
    git config --system --add safe.directory '*'

COPY entrypoint.sh backup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh

ENV REPOS_DIR=/repos \
    CRON_SCHEDULE="30 4 * * 1" \
    UPTIME_KUMA_URL="" \
    GIT_TIMEOUT=300 \
    IGNORE_REPOS="" \
    IGNORE_FILE="" \
    REPO_GROUPS="" \
    RUN_ON_STARTUP="true" \
    PUID=1000 \
    PGID=1000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
