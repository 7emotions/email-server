# Operations Guide — Mailu Email Server

> **Domain**: ugenrobot.com
> **Server**: 47.98.123.173
> **Mailu Version**: 2024.06 (stable)
> **Admin Panel**: https://mail.ugenrobot.com/admin
> **Webmail**: https://mail.ugenrobot.com/webmail (Roundcube)
> **Last Updated**: 2026-05-21

---

## Table of Contents

1. [Quick Reference](#1-quick-reference)
2. [Service Management](#2-service-management)
3. [User Management](#3-user-management)
4. [Email Management](#4-email-management)
5. [DKIM Management](#5-dkim-management)
6. [TLS Certificate Management](#6-tls-certificate-management)
7. [Monitoring](#7-monitoring)
8. [Spam Management](#8-spam-management)
9. [ClamAV Management](#9-clamav-management)
10. [Backup (Manual Steps)](#10-backup-manual-steps)
11. [Troubleshooting](#11-troubleshooting)
12. [Upgrade Procedure](#12-upgrade-procedure)
13. [SMTP Relay (Optional, Not Configured)](#13-smtp-relay-optional-not-configured)

---

## 1. Quick Reference

### Directory Structure

```
/opt/email-server/
  compose.yaml          # Docker Compose service definitions
  mailu.env             # All Mailu configuration variables
  .env                  # Overrides (created at deploy time)
  caddy/
    Caddyfile.mail      # Caddy reverse proxy config for mail.ugenrobot.com
  docs/
    DNS.md              # DNS record reference
    OPERATIONS.md       # This file
  scripts/
    preflight.sh        # Pre-deployment validation script
  data/                 # Persistent data (root defined by $ROOT in mailu.env)
```

### Key Files

| File | Purpose |
|------|---------|
| `compose.yaml` | Defines all 9 Docker services (front, admin, imap, smtp, antispam, antivirus, webmail, redis, resolver) |
| `mailu.env` | All Mailu configuration — manage users through the admin panel instead |
| `/etc/caddy/Caddyfile` | Root Caddy config, imports `caddy/Caddyfile.mail` |

### Data Directory Contents

All under `${ROOT:-./data}` (resolves to `/opt/email-server/data`):

| Path | Contents |
|------|----------|
| `data/` | SQLite databases (`main.db`, `roundcube.db`), user maildirs |
| `dkim/` | DKIM private/public key pair for each domain |
| `certs/` | TLS certificates (managed by acme.sh, mounted to front container) |
| `mail/` | User mail spool (Dovecot storage) |
| `mailqueue/` | Postfix mail queue |
| `redis/` | Redis persistence |
| `filter/` | Rspamd filter data |
| `clamav/` | ClamAV virus database |
| `webmail/` | Roundcube plugin config and cache |

### URLs

- **Main web interface**: https://mail.ugenrobot.com (redirects to `/admin`)
- **Admin panel**: https://mail.ugenrobot.com/admin
- **Webmail**: https://mail.ugenrobot.com/webmail
- **API**: https://mail.ugenrobot.com/api

### Important Ports

| Port | Service | Exposure |
|------|---------|----------|
| 25 | SMTP (inbound) | Public |
| 465 | SMTPS (submissions) | Public |
| 587 | SMTP submission (STARTTLS) | Public |
| 993 | IMAPS | Public |
| 8443 | HTTPS (admin, webmail) | Localhost only (via Caddy) |

---

## 2. Service Management

All commands run as root or with `sudo` from `/opt/email-server`. If you are in the directory, you can omit the `-f compose.yaml` flag.

### Check All Services

```bash
cd /opt/email-server
docker compose ps
```

Shows the status of all 9 containers. Every container should show `Up` (healthy) or `Up` (unhealthy for ClamAV during initial DB download). If any container is `Exit`, `Paused`, or `Restarting`, investigate.

### View Logs

```bash
# All services (follow)
docker compose logs -f

# Single service (last 50 lines, follow)
docker compose logs --tail=50 -f smtp

# Common services to watch:
docker compose logs --tail=50 -f front      # nginx — HTTP errors
docker compose logs --tail=50 -f smtp       # Postfix — delivery issues
docker compose logs --tail=50 -f antispam   # Rspamd — spam filtering
docker compose logs --tail=50 -f admin      # Flask — auth issues
docker compose logs --tail=50 -f antivirus  # ClamAV — virus scan
```

### Restart a Single Service

```bash
cd /opt/email-server
docker compose restart smtp
docker compose restart antispam
docker compose restart admin
```

Use this for minor changes or when a container is stuck. **Do NOT use this for config changes** to `mailu.env` or `compose.yaml` — those require a full down/up cycle (see below).

### Full Restart (for Config Changes)

If you modify `mailu.env` or `compose.yaml`, the containers need to be recreated. A plain `restart` does NOT pick up config changes.

```bash
cd /opt/email-server
docker compose down && docker compose up -d
```

This destroys and recreates all containers. Persistent data (mail, databases, certs) is safe in bind-mounted volumes under `data/`. After starting, check all services are healthy:

```bash
docker compose ps
```

### Update Container Images

```bash
cd /opt/email-server
docker compose pull
```

Downloads the latest images for all services without restarting. To apply the updates, follow the full restart procedure above.

---

## 3. User Management

User management is done through the admin web panel. The CLI is available for bulk operations but is less convenient.

### Add a New User

1. Go to **https://mail.ugenrobot.com/admin** and log in as `admin@ugenrobot.com`.
2. Go to **Users** (in the sidebar) then click **Add**.
3. Fill in:
   - **Email**: full email address (e.g., `user@ugenrobot.com`)
   - **Password**: set an initial password (user can change via webmail)
   - **Quota**: leave blank for unlimited, or set a limit (e.g., `1G`)
4. Click **Save**.

The user's maildir is created on first login or first incoming email. No additional steps are needed.

### Remove a User

**Step 1 — Deactivate in admin panel:**

1. Go to **Users** > find the user > click **Edit**.
2. Set **Status** to **Deactivated** (do not delete yet).
3. This prevents the user from logging in and rejects new mail delivery.

**Step 2 — Remove maildir (clean up disk):**

Deactivating does not free disk space. To delete the maildir, run:

```bash
docker compose exec admin flask mailu user delete user@ugenrobot.com
```

This removes the user from the database AND deletes their maildir. There is no undo.

### Set or Change Quota

1. Admin panel > **Users** > find the user > **Edit**.
2. Set **Quota** field. Use formats like `1G`, `500M`, `0` (unlimited).
3. Click **Save**.

Quota enforcement is handled by Dovecot. The user will see a warning when approaching the limit.

### List All Users

**Via admin panel:** Users section shows all accounts with their status and quota.

**Via CLI:**

```bash
docker compose exec admin flask mailu user list
```

Output shows email addresses and unique IDs. For more detail, check the admin panel.

### Change a User's Password

1. Admin panel > **Users** > find the user > **Edit**.
2. Enter a new password in the password field.
3. Click **Save**.

Or the user can change their own password via Roundcube webmail (Settings > Password).

---

## 4. Email Management

### View the Mail Queue

See what messages are waiting to be delivered:

```bash
docker compose exec smtp mailq
```

Output shows each queued message's ID, size, arrival time, sender, and recipient. An empty queue (or "Mail queue is empty") is normal.

### Flush the Queue

Force Postfix to attempt immediate delivery of all queued messages:

```bash
docker compose exec smtp postfix flush
```

Used after resolving a delivery issue (e.g., DNS was broken and has been fixed). Normal delivery retries happen automatically, so flushing is optional.

### Delete a Specific Message from the Queue

If a message is stuck (e.g., bouncing due to bad address), remove it:

```bash
docker compose exec smtp postsuper -d <queue-id>
```

Find the queue ID from the `mailq` output (first column). Example: `postsuper -d A3B4C5D6E7`.

### Delete All Queued Mail

```bash
docker compose exec smtp postsuper -d ALL
```

**Use with caution.** This removes ALL queued messages (incoming and outgoing).

### Search the Queue by Sender or Recipient

```bash
docker compose exec smtp mailq | grep user@domain.com
```

Or for a more detailed view:

```bash
docker compose exec smtp postqueue -p | grep user@domain.com
```

### Check Queue Size

```bash
docker compose exec smtp mailq | tail -1
```

If the queue has thousands of messages, something is wrong (likely a spam run or a misconfigured service sending from your server). Investigate immediately.

---

## 5. DKIM Management

DKIM signs outgoing emails with a private key. Receiving servers verify the signature using the public key published in DNS.

### View DKIM Status

1. Admin panel > **Domains** > click `ugenrobot.com`.
2. Scroll to the **DKIM** section.
3. You will see:
   - Whether DKIM is enabled.
   - The selector (default: `mail`).
   - The public key (if already generated).

### Generate the Initial DKIM Key

Must be done after the first Mailu deployment:

1. Admin panel > **Domains** > click `ugenrobot.com`.
2. Click **Generate DKIM key** (the button appears if no key exists).
3. Copy the displayed public key.
4. Add it as a DNS TXT record in DNSPod:
   - Host: `mail._domainkey`
   - Value: `v=DKIM1; k=rsa; p=<THE_KEY>`
   - TTL: 3600
5. Wait for DNS propagation (up to 1 hour), then verify:

```bash
dig TXT mail._domainkey.ugenrobot.com +short
```

### Rotate DKIM Keys (Every 6 Months)

Regular rotation reduces risk if a private key is compromised.

1. Admin panel > **Domains** > click `ugenrobot.com`.
2. Click **Generate DKIM key** again. This replaces the private key.
3. Copy the new public key and update the DNS TXT record in DNSPod.
4. Wait for DNS propagation.
5. **Do NOT delete the old DNS record immediately** — some email servers may have cached the old key. Wait at least 24 hours.
6. After 24 hours, the old key can be removed (the admin panel only stores one key at a time).

### DKIM Troubleshooting

If emails are not being DKIM-signed:

- Verify `DKIM_ENABLE` is implicitly enabled (Mailu enables it by default in 2024.06).
- Check the admin panel > Domain > DKIM section shows a key.
- Check logs: `docker compose logs --tail=50 admin`.
- Test with an external tool: https://www.dkimvalidator.com/

---

## 6. TLS Certificate Management

There are two separate TLS domains on this server: **web** (mail.ugenrobot.com HTTPS) and **mail** (SMTP/IMAP STARTTLS). They are managed differently.

### Web TLS (Caddy — Automatic)

Caddy handles HTTPS for `mail.ugenrobot.com` automatically via Let's Encrypt. You do not need to do anything:

- Certificate is auto-requested on first start.
- Auto-renewal is built into Caddy (no cron job needed).
- Certificates are stored in Caddy's default storage location (`/var/lib/caddy/.local/share/certificates/` or similar).

**Check the Caddy cert:**

```bash
sudo caddy cert-info mail.ugenrobot.com
```

Or check the admin panel loads with a valid certificate in your browser.

### Mail TLS (acme.sh — DNS-01 Challenge)

SMTP (port 587) and IMAP (port 993) use a separate certificate for `mail.ugenrobot.com`. This is managed by `acme.sh` with a DNS-01 challenge via Tencent Cloud DNSPod API.

**Why DNS-01?** The mail server cannot use port 80 for HTTP-01 (it is behind Caddy). DNS-01 uses the DNS API to prove domain ownership.

**Certificate location:** The cert is copied to the Mailu certs directory so the front container can use it:

```
/opt/email-server/data/certs/
```

**Check certificate expiry:**

```bash
echo | openssl s_client -connect localhost:587 -starttls smtp 2>/dev/null | openssl x509 -noout -dates
```

Look for `notBefore=` and `notAfter=` in the output. Renew if the expiry is within 30 days.

**Manual renewal:**

```bash
acme.sh --renew -d mail.ugenrobot.com --dns dns_dp
```

This triggers a renewal even if the cert is not yet due. The `dns_dp` flag tells acme.sh to use the Tencent Cloud DNSPod DNS-01 API.

**Note:** acme.sh is configured with a cron job for automatic renewal. The manual command is only needed if auto-renewal fails.

---

## 7. Monitoring

### Container Health

```bash
cd /opt/email-server
docker compose ps
```

Every service should be `Up` or `Up (healthy)`. If any show `Exit`, `Restarting`, or `Paused`, investigate.

### Disk Usage

```bash
# Data directory
df -h /opt/email-server/data

# Overall system
df -h /

# Largest directories in data
du -sh /opt/email-server/data/*/ | sort -hr
```

The mail spool (`data/mail/`) grows over time. Plan to add disk or archive old mail when usage exceeds 80%.

### Memory Usage

```bash
# Per-container resource usage
docker stats --no-stream

# System memory
free -h
```

Mailu uses roughly:
- 400-800 MB for ClamAV (the largest consumer)
- 200-400 MB for the rest combined
- Total: ~1-1.5 GB at idle

### Swap Usage

```bash
swapon --show
```

If swap usage is consistently above 0, the server needs more RAM. ClamAV is usually the culprit.

### Mail Queue Size

```bash
docker compose exec smtp mailq | tail -1
```

A healthy queue has 0 or a small number of messages. A growing queue indicates a delivery problem.

### Logs — Quick Diagnostics

```bash
# Recent errors across all services
docker compose logs --tail=50 | grep -i error

# SMTP delivery failures
docker compose logs --tail=50 smtp | grep -i "rejected\|bounced\|failed"

# IMAP login failures
docker compose logs --tail=50 imap | grep -i "failed login\|auth failed"
```

### Connectivity Tests

```bash
# Can the server connect outbound on port 25?
timeout 5 bash -c 'echo | openssl s_client -connect gmail-smtp-in.l.google.com:25 -starttls smtp' 2>/dev/null | head -20

# Is port 25 open inbound?
nc -zv 47.98.123.173 25
```

---

## 8. Spam Management

Spam filtering is handled by **Rspamd**, which works in conjunction with the Postfix SMTP server.

### View Spam Scores

1. Admin panel > **Logs** > **Rspamd History**.
2. You will see recent messages with their spam scores.
3. Each message shows the symbolic name (e.g., `BAYES_SPAM`, `DKIM_VALID`) and the points assigned.
4. Messages scoring above the threshold (default 80, but 80 is very high — it is the **symbolic** score, not a percentage) are rejected.

Rspamd uses a complex scoring system. In practice:

- Scores under 20: likely ham (legitimate).
- Scores 20-80: suspicious but delivered.
- Scores over 80: rejected as spam.

### Adjust the Spam Threshold

1. Admin panel > **Settings** > find `DEFAULT_SPAM_THRESHOLD`.
2. Current value: `80` (defined in `mailu.env`).
3. Lower = more aggressive filtering. Higher = more lenient.
4. If legitimate mail is being marked as spam, lower the value (try `50`).
5. If spam is getting through, raise the value (try `100`).
6. Click **Save** and restart the antispam container:

```bash
docker compose restart antispam
```

### Whitelist a Sender

To ensure a specific sender is never marked as spam:

1. Admin panel > **Anti-spam** > **Whitelist**.
2. Add the sender's email address or domain.
3. Click **Save**.

Changes take effect immediately without a restart.

### Rspamd Web Interface

Rspamd has its own web interface on port 11334 (internal to the Docker network only). It is not exposed publicly.

To access it from the server:

```bash
curl http://antispam:11334/
```

Or use port forwarding:

```bash
ssh -L 11334:localhost:11334 user@47.98.123.173
# Then visit http://localhost:11334 in your browser
```

### Check Spam Quarantine

Rspamd does not quarantine messages by default — it rejects them at the SMTP level. If you want to review what was rejected, check the SMTP logs:

```bash
docker compose logs --tail=100 smtp | grep "rejected\|spam"
```

---

## 9. ClamAV Management

ClamAV scans incoming email attachments for viruses. It runs in a separate container (`antivirus`) with a 1 GB memory limit.

### Check ClamAV Version

```bash
docker compose exec antivirus clamscan --version
```

### Check Virus Database Version

```bash
docker compose exec antivirus freshclam --version
```

Output shows the database version and the number of signatures. The database should be updated daily via `freshclam` (automatic).

### Initial Database Download

On first start, ClamAV downloads a ~100 MB virus database. This takes **5-15 minutes** depending on network speed. During this time, the container is unhealthy and does not scan. Email delivery still works — it just passes through without virus scanning.

Monitor progress:

```bash
docker compose logs --tail=50 -f antivirus
```

You will see lines like:

```
Downloading daily.cvd (68%): 68 MiB / 100 MiB
```

### ClamAV Runs Out of Memory (OOM)

ClamAV is memory-hungry. On a 2 GB server, it may crash with an OOM error. Symptoms:

- The `antivirus` container shows `Exit 137` (SIGKILL due to OOM).
- Logs contain `fatal error: Cannot allocate memory`.

**Option A: Reduce memory pressure**

Add `/etc/clamav/clamd.conf` with `MaxThreads 1` and `MaxConnectionQueueLength 5` via a custom config volume.

**Option B: Disable ClamAV entirely**

1. Set `ANTIVIRUS=none` in `mailu.env`.
2. Comment out or remove the `antivirus` service from `compose.yaml`.
3. Run `docker compose down && docker compose up -d`.

Your server still works. Spam detection (Rspamd) continues without ClamAV. Only attachment malware scanning is lost.

---

## 10. Backup (Manual Steps)

### What to Back Up

| Path | Importance | Notes |
|------|------------|-------|
| `data/data/main.db` | Critical | SQLite database — all users, domains, aliases |
| `data/data/roundcube.db` | Important | Roundcube settings, address books |
| `data/dkim/` | Critical | DKIM private keys — if lost, re-rotate DNS |
| `data/certs/` | Important | TLS certs — can be reissued via acme.sh |
| `mailu.env` | Critical | All configuration (keep a copy off-server) |

### What NOT to Back Up

| Path | Reason |
|------|--------|
| `data/mail/` | Too large; can be re-downloaded via IMAP |
| `data/clamav/` | Re-downloaded by freshclam |
| `data/redis/` | Transient cache |
| `data/mailqueue/` | Transient queue |

### Backup Command

```bash
cd /opt/email-server
tar czf backup-$(date +%Y%m%d).tar.gz \
  -C data data/dkim data/certs \
  mailu.env
```

This creates a compressed archive of the essentials.

For a more complete backup (including the database):

```bash
cd /opt/email-server
docker compose exec admin flask mailu backup > mailu-backup-$(date +%Y%m%d).json
tar czf backup-$(date +%Y%m%d).tar.gz \
  -C data data/dkim data/certs \
  mailu.env \
  mailu-backup-$(date +%Y%m%d).json
```

### Restore from Backup

1. Deploy a fresh Mailu instance.
2. Stop all services: `docker compose down`.
3. Replace `data/dkim/` and `data/certs/` from the backup.
4. Replace `mailu.env`.
5. If you have a `flask mailu backup` export, restore it:

```bash
docker compose exec admin flask mailu import < mailu-backup-YYYYMMDD.json
```

6. Start services: `docker compose up -d`.

### Off-Site Storage

Copy the backup archive to another machine or cloud storage:

```bash
scp backup-20260521.tar.gz user@offsite-backup-server:~/
```

---

## 11. Troubleshooting

### Container Won't Start

```bash
cd /opt/email-server
docker compose logs <service-name>
```

Common causes:

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Port conflict | Another service is on port 25/465/587/993 | `sudo ss -tlnp` to find the offender, then stop it |
| Config error | Invalid `mailu.env` | Check for typos, re-run `docker compose config` |
| Volume permission | Bind mount dirs have wrong ownership | `chown -R 1000:1000 data/` (Mailu runs as UID 1000) |
| ClamAV OOM | Not enough RAM | Disable ClamAV (see [ClamAV section](#9-clamav-management)) |

### Can't Send Email

Check outbound port 25:

```bash
timeout 5 bash -c 'echo | openssl s_client -connect gmail-smtp-in.l.google.com:25 -starttls smtp' 2>/dev/null | head -20
```

If the connection times out:

- Your VPS provider may be blocking port 25 outbound (common with Alibaba Cloud, AWS, GCP).
- Check with your provider: they may need to unblock port 25 on request.
- Workaround: use an SMTP relay (see [SMTP Relay section](#13-smtp-relay-optional-not-configured)).

If the connection succeeds but mail is rejected, check:

- SPF record: `dig TXT ugenrobot.com +short`
- PTR/reverse DNS: `dig -x 47.98.123.173 +short` (must return `mail.ugenrobot.com.`)
- IP reputation: use MXToolbox blacklist checker

### Can't Receive Email

Check inbound port 25 from an external machine:

```bash
nc -zv 47.98.123.173 25
```

If it fails:

- Check the VPS firewall / security group: port 25 must be open for inbound traffic.
- Check Docker port publishing: `docker compose ps` should show `0.0.0.0:25->25/tcp`.
- Check the service: `docker compose logs front | grep 25`.

If port 25 is open but email is not delivered to users:

- Check MX records: `dig MX ugenrobot.com +short` (must show `10 mail.ugenrobot.com.`).
- Check the recipient user exists in the admin panel.
- Check `postmaster@ugenrobot.com` exists as an alias or user (see below).

### "Strange Errors" in Logs

The most common cause is a **missing postmaster alias**. Many Mailu services (DMARC reports, TLS-RPT reports, bounce handling) send email to `postmaster@ugenrobot.com`. If this address does not exist, you get cryptic errors in the logs.

**Fix:**

1. Admin panel > **Aliases** > **Add**.
2. Set **Alias**: `postmaster@ugenrobot.com`.
3. Set **Destination**: your actual email address (or `admin@ugenrobot.com`).
4. Click **Save**.

### Let's Encrypt Failure (Web TLS)

If the Caddy reverse proxy fails to get a Let's Encrypt certificate:

1. Check port 80 is reachable from the internet (Caddy uses HTTP-01).
2. Check `mail.ugenrobot.com` resolves to `47.98.123.173`:

```bash
dig A mail.ugenrobot.com +short
```

3. Check Caddy logs:

```bash
journalctl -u caddy --no-pager --tail=50
```

4. Force a renewal:

```bash
sudo caddy renew
```

### Postfix Rate Limiting

If an application is sending too many emails, Postfix may hit the rate limit (`MESSAGE_RATELIMIT=200/hour` in `mailu.env`). Symptoms:

- Some emails are rejected with "rate limit exceeded".
- Check logs: `docker compose logs smtp | grep "rate limit"`.

To increase the limit, edit `mailu.env`, change `MESSAGE_RATELIMIT`, and restart all services.

---

## 12. Upgrade Procedure

Upgrading Mailu involves pulling new container images and recreating the containers. Data is safe in the bind-mounted volumes.

### Full Upgrade

**Step 1: Pull new images**

```bash
cd /opt/email-server
docker compose pull
```

This downloads the latest `2024.06` patch versions (or the tag you are pinned to). If upgrading to a new major version, change the image tags in `compose.yaml` first.

**Step 2: Check the changelog**

https://mailu.io/2024.06/releases.html

Look for:
- Breaking config changes.
- Database migration steps.
- Deprecated settings.

**Step 3: Recreate containers**

```bash
docker compose down && docker compose up -d
```

This destroys old containers and creates new ones with fresh images. Persistent data is preserved in the `data/` directory.

**Step 4: Verify**

```bash
cd /opt/email-server

# All containers healthy?
docker compose ps

# Admin panel accessible?
curl -s -o /dev/null -w "%{http_code}" https://mail.ugenrobot.com/admin

# Check all logs for errors
docker compose logs --tail=20 | grep -i error
```

### Minor Version Patch

If you are on `2024.06` and there is a new `2024.06` patch release, the `docker compose pull` command automatically picks it up because the tag is `2024.06` (not a specific build). Docker Compose resolves this to the latest build for that tag.

### Major Version Upgrade

To upgrade to a new major version (e.g., `2025.01`):

1. Edit `compose.yaml` and change all `:2024.06` tags to `:2025.01`.
2. Check `mailu.env` for any new or changed variables in the new version.
3. Follow the upgrade steps above.
4. Check the Mailu release notes for migration steps.

---

## 13. SMTP Relay (Optional, Not Configured)

This server sends email directly to recipient mail servers. If direct delivery causes problems (IP reputation, port 25 blocking), configure an SMTP relay.

### When to Use a Relay

- Your VPS provider blocks outbound port 25.
- Your IP is on an email blacklist.
- You need higher delivery reliability for transactional email.

### How to Configure

Edit `mailu.env`:

```
RELAYHOST=[smtp.sendgrid.net]:587
RELAYUSER=apikey
RELAYPASSWORD=your-api-key
```

**Security note:** Do not put the password directly in `mailu.env` if the file is not properly secured. Use a Docker secret instead:

```bash
echo "your-api-key" | docker secret create smtp_relay_password -
```

Then reference the secret in `compose.yaml` for the `smtp` service.

After changing these values, restart all services:

```bash
docker compose down && docker compose up -d
```

### Relay Providers

| Provider | Free Tier | Notes |
|----------|-----------|-------|
| SendGrid | 100 emails/day | Easy setup, good reputation |
| Amazon SES | 62,000/month if from EC2 | Requires AWS account |
| Mailgun | 100 emails/day | Good API, easy integration |
| Mailjet | 200 emails/day | EU provider, good support |

Choose one that supports STARTTLS on port 587 or 2525 (not all providers allow port 25 relaying).

---

## Appendix: Useful Docker Commands

```bash
# Enter a running container
docker compose exec admin sh

# Run a one-off command in a container
docker compose exec admin flask mailu user list

# View container resource usage
docker stats --no-stream

# View container details (IP, network, mounts)
docker compose ps -a

# Clean up old/unused images (frees disk)
docker image prune -a
```

## Appendix: File Locations Reference

| What | Where |
|------|-------|
| Compose file | `/opt/email-server/compose.yaml` |
| Environment config | `/opt/email-server/mailu.env` |
| Caddy mail config | `/opt/email-server/caddy/Caddyfile.mail` |
| Caddy root config | `/etc/caddy/Caddyfile` |
| Pre-flight checks | `/opt/email-server/scripts/preflight.sh` |
| SQLite databases | `/opt/email-server/data/data/` |
| DKIM keys | `/opt/email-server/data/dkim/` |
| TLS certs | `/opt/email-server/data/certs/` |
| Mail spool | `/opt/email-server/data/mail/` |
| DNS docs | `/opt/email-server/docs/DNS.md` |
