# Local Bitwarden server (Vaultwarden)

Self-hosted password manager on this Raspberry Pi (`octo35services`, aarch64), run with Docker Compose and served over HTTPS through Tailscale.

**Why Vaultwarden and not the official Bitwarden stack?** The official server is x86-64 only and needs Microsoft SQL Server plus ~10 containers. Vaultwarden is a lightweight, API-compatible reimplementation (SQLite, one container). All official Bitwarden clients (browser extensions, desktop, mobile, CLI) work with it.

## Layout

```
bitwarden/
├── docker-compose.yml     # vaultwarden only (127.0.0.1:8080)
├── .env                   # live settings + secrets (chmod 600, not shared)
├── .env.example           # template for .env
├── .gitignore             # keeps .env, data/, backups/ out of git
├── data/                  # ALL persistent state (chmod 700)
│   └── vaultwarden/       #   db.sqlite3, attachments/, sends/, rsa_key*, config.json
├── backups/               # local staging for backup archives (chmod 700)
└── scripts/
    └── backup.sh          # STUB - remote scp backup, not implemented yet
```

Everything worth backing up is in `data/`, `.env`, and `docker-compose.yml`. Nothing lives in Docker named volumes. The HTTPS proxy is **not** part of this project, it lives in `../caddy`.

## How HTTPS works

```
device on tailnet ──https──► Caddy (../caddy, host network, port 443, path /vaultwarden)
                                   │  certificate: Let's Encrypt, fetched
                                   │  from the local tailscaled (*.ts.net)
                                   ▼
                          127.0.0.1:8080 ──► vaultwarden container
```

Bitwarden clients need HTTPS (browser WebCrypto only works in a secure context). Tailscale issues a real certificate for this machine's MagicDNS name, so **no CA has to be installed on any device**. Caddy gets and renews it automatically through the mounted `tailscaled.sock`.

- Vault URL: **`https://octo35services.tail19e18b.ts.net/vaultwarden`** (same name and port as the landing page, Vaultwarden lives under the `/vaultwarden` sub-path)
- Use the name, not the IP: the certificate only matches the name.
- Vaultwarden publishes only on `127.0.0.1`, so it is not reachable directly from the network.
- Requires "HTTPS Certificates" enabled in the Tailscale admin console (DNS page). Already done.
- The hostname ends up in public Certificate Transparency logs (name only, not content).
- Plain HTTP to the Tailscale name is redirected to HTTPS, and Vaultwarden is never served over plain HTTP.
- The Caddy side (Caddyfile, `TS_DOMAIN`, the socket mount) is documented in `../caddy/README.md`.

`DOMAIN` in `.env` must equal the URL above **including `/vaultwarden`**. Vaultwarden is told its sub-path through `DOMAIN`, and Caddy passes the prefix through unchanged. If you change the path or name, change it in both `.env` here and `../caddy/Caddyfile`.

## First-time setup

```sh
cd /home/services/Documents/bitwarden
cp .env.example .env            # then set DOMAIN, TZ
docker compose up -d
docker compose logs -f
```

1. Open `https://octo35services.tail19e18b.ts.net/vaultwarden` from a device on the tailnet and create your account.
2. **Lock registration:** in `.env` set `SIGNUPS_ALLOWED=false`, then `docker compose up -d`.
3. In a Bitwarden client choose "self-hosted" and enter the server URL.

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

## Sharing with other people

The URL is the same for everyone; each person has their own account and vault (share items deliberately via a Bitwarden Organization).

- **People on your tailnet:** just give them the URL.
- **Someone on another tailnet (Tailscale node sharing):** share this node with them; they use the same full `...ts.net/vaultwarden` name. Not tested yet, try it with one person first.
- **New accounts** need either `SIGNUPS_ALLOWED=true` for a moment, or an invitation from the admin panel (enable `ADMIN_TOKEN` first).

**Sharing this node exposes the whole Pi**, not just Vaultwarden: OctoPrint (`:91`), the filament tool (`:81`), Portainer (`:9443`) and plain HTTP (`:80`) also listen on all interfaces. In the tailnet policy, limit shared users to HTTPS only, for example (adapt to your policy format, `someone@example.com` is a placeholder):

```json
{
  "grants": [
    {
      "src": ["someone@example.com"],
      "dst": ["octo35services"],
      "ip":  ["tcp:443"]
    }
  ]
}
```

## Configuration reference (`.env`)

| Variable | Purpose |
|---|---|
| `DOMAIN` | Full public URL incl. sub-path, `https://<ts-name>/vaultwarden` |
| `VAULTWARDEN_PORT` | Localhost port Caddy proxies to (default 8080) |
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
| Compose + settings | `docker-compose.yml`, `.env` | `.env` contains secrets |

`../caddy` is versioned in git and holds no state worth backing up (certificates are re-fetched from Tailscale).

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
2. Extract the archive into the project directory (restores `data/`, `.env`, `docker-compose.yml`).
3. `docker compose up -d`

Test a restore once the backup exists; an untested backup is not a backup.

## Security notes

- `data/`, `backups/` are `chmod 700`; `.env` is `chmod 600`.
- Vaultwarden has no network-facing port; the only entry point is Caddy over HTTPS.
- Keep `SIGNUPS_ALLOWED=false` after your accounts exist.
- Do not enable Tailscale Funnel for this: it would expose the vault to the public internet.
- Enable 2FA on your account.
- Keep an offline copy of your master password and recovery info: neither Vaultwarden nor a backup can recover a forgotten master password.
