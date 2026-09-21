#!/usr/bin/env bash
# Backup of Vaultwarden data + config to a remote host via scp.
#
# STATUS: NOT IMPLEMENTED YET. This stub only records the intended design so
# the README, .env and folder layout are ready for it. See README "Backups".
#
# Planned steps:
#   1. Load .env (BACKUP_* settings); exit quietly if BACKUP_ENABLED != true.
#   2. Consistent DB snapshot (never copy a live SQLite file):
#        docker compose exec vaultwarden sqlite3 /data/db.sqlite3 \
#          ".backup '/data/db-backup.sqlite3'"
#      (or `docker compose stop vaultwarden` for the duration of the copy).
#   3. tar+gzip into $BACKUP_LOCAL_DIR/vaultwarden-<timestamp>.tar.gz:
#        the snapshot, data/vaultwarden/{attachments,sends,rsa_key*,config.json},
#        .env, docker-compose.yml, Caddyfile, data/caddy/data (local CA).
#      Optionally encrypt (age/gpg) before leaving the machine.
#   4. scp the archive to $BACKUP_SCP_USER@$BACKUP_SCP_HOST:$BACKUP_SCP_PATH
#      using $BACKUP_SCP_KEY and $BACKUP_SCP_PORT.
#   5. Prune local archives older than $BACKUP_RETENTION_DAYS.
#   6. Schedule with cron / systemd timer.

set -euo pipefail

echo "backup.sh: not implemented yet. See README.md ('Backups')." >&2
exit 1
