# Git Backup Docker Service

A lightweight container that periodically runs `git pull --ff-only` on every
repository inside a host directory, creating a local rollback copy in case a
remote disappears. Invalid folders, bare repositories, or repositories without
an accessible remote are skipped and logged.

## Quick start

1. Copy `.env.example` to `.env` and fill in `REPOS_HOST_PATH` and `PUID`/`PGID`
   to match the owner of your repos directory (run `id` on the host to check).
2. Optionally set `UPTIME_KUMA_URL` for failure notifications.
3. Build and start:

```bash
docker compose up -d --build
```

View live logs:

```bash
docker logs -f git-backup
```

Run a backup manually inside the container:

```bash
docker exec -u 1000 git-backup /usr/local/bin/backup.sh
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `REPOS_HOST_PATH` | — | **Required.** Host path mounted into the container as `/repos`. |
| `CRON_SCHEDULE` | `30 4 * * 1` | Cron expression. Default: Monday 04:30. |
| `REPOS_DIR` | `/repos` | Path inside the container. Keep in sync with the volume mount. |
| `UPTIME_KUMA_URL` | `""` | Uptime Kuma push monitor URL. Empty = disabled. |
| `IGNORE_REPOS` | `""` | Comma-separated list of repo directory names to ignore entirely. |
| `IGNORE_FILE` | `<REPOS_DIR>/.git-backup-ignore` | Path to a file with one repo name per line (`#` comments allowed). |
| `REPO_GROUPS` | `""` | Comma-separated directory names that contain repos instead of being repos themselves. Each is recursed one level deep. |
| `PUID` / `PGID` | `1000` / `1000` | User/Group IDs used for git operations. Must match the host owner of `REPOS_HOST_PATH`. |
| `TZ` | — | Timezone for the cron schedule, e.g. `Europe/Berlin`. |
| `RUN_ON_STARTUP` | `true` | Run one backup immediately when the container starts. |
| `GIT_TIMEOUT` | `300` | Seconds to wait per git operation. |

## Workflow

**Adding repos:** Clone them by hand into `REPOS_HOST_PATH`. The service picks them up on the next run — no restart needed.

```bash
git clone https://github.com/example/repo /path/to/your/repos/repo
```

**Repo groups:** If you have a directory containing multiple repos (e.g. you cloned a whole GitHub organisation manually), add the directory name to `REPO_GROUPS` in `.env`. The service will recurse one level into it.

**When Uptime Kuma sends a failure ping:**
1. Check `docker logs git-backup` for the `ERROR:` or `SKIP:` line.
2. If the remote was taken down and you no longer need updates, add the repo name to `IGNORE_REPOS` in `.env` and redeploy (`docker compose up -d`). The error will stop.
3. If it is a transient network issue or a `git pull` conflict, investigate and resolve manually — the next scheduled run will retry.

## Logs

All output goes to Docker's log stream — no files written inside the container.

```bash
docker logs -f git-backup
```

## What gets skipped

The script checks each subfolder in `REPOS_DIR`:

1. Not a git repository → logged as `SKIP: ... is not a valid git repository`
2. Bare repository → logged as `SKIP: ... is a bare repository`
3. No `origin` remote → logged as `SKIP: ... has no origin remote`
4. Remote not reachable → logged as `SKIP: ... remote is not accessible`

An example like `winamp.2024-09-27` (a bare/malformed `.git` folder) will be
skipped and logged. If you want to permanently silence such folders, add them
to `IGNORE_REPOS` or create a `.git-backup-ignore` file in the repos directory.

## Failure handling

- Any `git pull` failure is logged.
- If `UPTIME_KUMA_URL` is set, a `status=down` ping is sent with the repository name in the message.
- When the whole run succeeds, a `status=up` ping is sent.
- A file lock prevents overlapping runs.
