# Local Bitwarden server (Vaultwarden)

Self-hosted password manager on this Raspberry Pi (`octo35services`, aarch64), run with Docker Compose.

**Why Vaultwarden and not the official Bitwarden stack?** The official server is x86-64 only and needs Microsoft SQL Server plus ~10 containers. Vaultwarden is a lightweight, API-compatible reimplementation (SQLite, one container). All official Bitwarden clients (browser extensions, desktop, mobile, CLI) work with it.

## Layout

```
bitwarden/
├── docker-compose.yml     # vaultwarden + caddy (HTTPS reverse proxy)
├── Caddyfile              # Caddy config, local-CA TLS on $HTTPS_PORT
├── .env                   # live settings + secrets (chmod 600, not shared)
├── .env.example           # template for .env
├── .gitignore             # keeps .env, data/, backups/ out of git
├── data/                  # ALL persistent state (chmod 700)
│   ├── vaultwarden/       #   db.sqlite3, attachments/, sends/, rsa_key*, config.json
│   └── caddy/
│       ├── data/          #   local CA + issued certs
│       └── config/
├── backups/               # local staging for backup archives (chmod 700)
└── scripts/
    └── backup.sh          # STUB - remote scp backup, not implemented yet
```

Everything worth backing up is in `data/`, `.env`, and the three config files. Nothing lives in Docker named volumes.

## Access

| What | Value |
|---|---|
| Web vault | `https://octo35services:8443` (or `https://192.168.178.186:8443`) |
| Vaultwarden | internal only, no published port |
| HTTPS port | `8443` (port 80 is already used by another service, 9443 by Portainer) |

The hostname/IP you use **must match `DOMAIN_HOST` / `DOMAIN` in `.env`**. If you want to use the IP or a different name, change those, then `docker compose up -d`.

### Why HTTPS and a local CA

Bitwarden clients rely on the browser's WebCrypto API, which only works in a secure context (HTTPS, or `localhost`). So plain HTTP over the LAN will not work. Caddy issues a certificate from its own private CA (`tls internal`). Each device that uses the vault must trust that CA once:

```sh
# Root certificate to copy to your devices:
data/caddy/data/caddy/pki/authorities/local/root.crt
```

Import it into the OS / browser trust store (and on phones: install as a CA certificate). The file appears after the first start.

Alternative: put it behind Tailscale (this host is already on a tailnet) with `tailscale cert` / a Tailscale HTTPS name, and swap the `tls internal` line in the `Caddyfile` for those cert files.

## First-time setup

```sh
cd /home/services/Documents/bitwarden
docker compose up -d
docker compose logs -f          # wait for Vaultwarden + Caddy to be ready
```

1. Trust the Caddy root cert on your device (above).
2. Open `https://octo35services:8443` and create your account.
3. **Lock registration:** in `.env` set `SIGNUPS_ALLOWED=false`, then `docker compose up -d`.
4. In a Bitwarden client, choose "self-hosted" and enter the server URL.

## Day-to-day

```sh
docker compose up -d                 # start / apply .env changes
docker compose down                  # stop (data stays in ./data)
docker compose logs -f vaultwarden
docker compose ps
```

### Updating

```sh
docker compose pull && docker compose up -d
```

`VAULTWARDEN_VERSION=latest` follows upstream. For controlled upgrades pin a version in `.env`. **Take a backup before upgrading** (Vaultwarden may migrate the DB schema).

### Admin panel (optional, off by default)

The `/admin` page is disabled while `ADMIN_TOKEN` is empty. To enable, generate an argon2 hash:

```sh
docker run --rm -it vaultwarden/server /vaultwarden hash
```

Paste the resulting `$argon2id$...` string into `ADMIN_TOKEN=` in `.env`, **replacing every `$` with `$$`** (Compose treats `$` as interpolation), then `docker compose up -d`.

## Configuration reference (`.env`)

| Variable | Purpose |
|---|---|
| `DOMAIN_HOST` | Hostname/IP Caddy serves and clients connect to |
| `HTTPS_PORT` | Host port for HTTPS (default 8443) |
| `DOMAIN` | Full `https://host:port` URL, keep consistent with the two above |
| `TZ` | Timezone (`Europe/Berlin`) |
| `VAULTWARDEN_VERSION` | Image tag (`latest` or pinned) |
| `SIGNUPS_ALLOWED` | `true` only while creating accounts |
| `ADMIN_TOKEN` | Argon2 hash to enable `/admin`; empty = disabled |
| `BACKUP_*` | Reserved for the remote backup, see below |

## Backups

**Status: planned, not built.** The structure and settings are in place; `scripts/backup.sh` is a stub that exits with an error and lists the intended steps.

### What must be backed up

| Item | Path | Notes |
|---|---|---|
| Database | `data/vaultwarden/db.sqlite3` | Take a consistent snapshot; **do not copy the live file** (see below) |
| Attachments / Sends | `data/vaultwarden/attachments/`, `sends/` | |
| RSA keys | `data/vaultwarden/rsa_key*` | Needed for sessions/tokens |
| Runtime config | `data/vaultwarden/config.json` | Present if the admin panel was used |
| Compose + settings | `docker-compose.yml`, `Caddyfile`, `.env` | `.env` contains secrets |
| Local CA | `data/caddy/data/` | Keeps the same CA so devices don't need to re-trust |

The backup contains everything needed to read the vault (though still encrypted by your master password), so **encrypt the archive** (e.g. `age` or `gpg`) before it leaves the machine.

### Planned design

1. `sqlite3 .backup` inside the container to make a consistent DB copy (or stop the container briefly).
2. `tar.gz` everything above to `backups/vaultwarden-<timestamp>.tar.gz`, optionally encrypted.
3. `scp` to the remote destination using a dedicated SSH key.
4. Delete local archives older than `BACKUP_RETENTION_DAYS`.
5. Run nightly via cron or a systemd timer.

### Settings to fill in when implementing (`.env`)

```
BACKUP_ENABLED=false            # flip to true when the script exists
BACKUP_LOCAL_DIR=./backups
BACKUP_RETENTION_DAYS=30
BACKUP_SCP_HOST=                # remote host
BACKUP_SCP_PORT=22
BACKUP_SCP_USER=
BACKUP_SCP_PATH=                # remote directory
BACKUP_SCP_KEY=~/.ssh/id_ed25519_bitwarden_backup
```

Suggested: create a dedicated key (`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_bitwarden_backup`) and restrict it on the remote side to the backup directory.

### Restore (outline)

1. `docker compose down`
2. Extract the archive into the project directory (restores `data/`, `.env`, config files).
3. `docker compose up -d`

Test a restore once the backup exists; an untested backup is not a backup.

## Security notes

- `data/`, `backups/` are `chmod 700`; `.env` is `chmod 600`.
- Vaultwarden has no host port; the only entry point is Caddy on `HTTPS_PORT`. Do not forward that port to the internet without deciding to.
- Keep `SIGNUPS_ALLOWED=false` after your accounts exist.
- Enable 2FA on your account.
- Keep an offline copy of your master password and recovery info: neither Vaultwarden nor a backup can recover a forgotten master password.
