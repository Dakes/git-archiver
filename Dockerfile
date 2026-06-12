FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    tzdata && \
    git config --system --add safe.directory '*'

COPY entrypoint.sh backup.sh lib.sh process-repo.sh github-repos.sh github-sync.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh \
             /usr/local/bin/process-repo.sh /usr/local/bin/github-repos.sh \
             /usr/local/bin/github-sync.sh

ENV REPOS_DIR=/repos \
    CRON_SCHEDULE="30 4 * * 1" \
    UPTIME_KUMA_URL="" \
    GIT_TIMEOUT=300 \
    IGNORE_REPOS="" \
    IGNORE_FILE="" \
    REPO_GROUPS="" \
    GITHUB_SOURCES="" \
    GITHUB_SKIP_FORKS="true" \
    GITHUB_SKIP_ARCHIVED="false" \
    RUN_ON_STARTUP="true" \
    PUID=1000 \
    PGID=1000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
