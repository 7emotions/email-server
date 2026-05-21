# Mailu Email Server -- ugenrobot.com

Production-grade self-hosted email server for ugenrobot.com, deployed on Alibaba Cloud ECS using Docker Compose. Serves SMTP (Postfix), IMAP (Dovecot), webmail (Roundcube), spam filtering (Rspamd), and antivirus (ClamAV), fronted by Caddy for TLS termination.

## Architecture

```
Internet
   |
   +-- Port 25/465/587/993 ----> Docker: mailu-front (nginx)
   |                               +-- admin (Flask UI)
   |                               +-- smtp (Postfix)
   |                               +-- imap (Dovecot)
   |                               +-- antispam (Rspamd)
   |                               +-- antivirus (ClamAV)
   |                               +-- webmail (Roundcube)
   |                               +-- resolver (Unbound)
   |                               +-- redis (Cache)
   |
   +-- Port 80/443 ----> Caddy (systemd)
                           +-- mail.ugenrobot.com ---> 127.0.0.1:8443 (front web)
```

Web traffic (80/443) goes through Caddy, which reverse proxies to the Mailu front container on localhost:8443. Mail ports (25, 465, 587, 993) are exposed directly by the Docker container.

## Prerequisites

- Docker >= 24.0.0, Docker Compose >= 2.0
- 4 GiB RAM minimum (Mailu + ClamAV need it)
- Server with static public IP
- Open ports: 25, 465, 587, 993 (inbound firewall)
- Domain DNS managed via Tencent Cloud DNSPod
- Caddy installed (for reverse proxy and TLS)

## Quick Start

1. Clone this repository to the target server.
2. `cp .env.example mailu.env` and edit for your domain, private IP, and secret key.
3. Configure DNS A/MX records for your domain (see [docs/DNS.md](docs/DNS.md)).
4. Run `scripts/preflight.sh` on the target server to verify readiness.
5. `docker compose up -d` to start all services.
6. Access the admin panel at `https://mail.ugenrobot.com/admin`.
7. Generate DKIM keys in the admin panel domain settings, then add the public key to DNS.
8. Run `scripts/verify.sh` to confirm the deployment is working.

## Project Structure

```
compose.yaml         Docker Compose service definitions
.env.example         Environment variable template (safe to commit)
mailu.env            Actual environment variables (gitignored)
caddy/
  Caddyfile.mail     Reverse proxy config for mail.ugenrobot.com
scripts/
  preflight.sh       Pre-deployment server validation (10 checks)
  verify.sh          Post-deployment verification (TODO)
docs/
  DNS.md             Full DNS configuration guide (Tencent Cloud DNSPod)
  OPERATIONS.md      Day-to-day operations guide (TODO)
```

## Configuration Reference

Key variables in `mailu.env`:

| Variable | Value | Note |
|----------|-------|------|
| `DOMAIN` | `ugenrobot.com` | Your domain |
| `HOSTNAMES` | `mail.ugenrobot.com` | Mail server hostname |
| `BIND_ADDRESS4` | `172.25.10.56` | Server private IP (not 0.0.0.0) |
| `TLS_FLAVOR` | `cert` | Manual cert management via acme.sh DNS-01 |
| `ANTIVIRUS` | `clamav` | ClamAV antivirus enabled |
| `WEBMAIL` | `roundcube` | Roundcube webmail enabled |
| `SUBNET` | `192.168.203.0/24` | Docker internal network |

Must stay **empty** (not unset, explicitly blank):

- `RELAYNETS` -- leaving this populated creates an open relay
- `BIND_ADDRESS6` -- IPv6 disabled
- `SUBNET6` -- IPv6 disabled

## URLs

| Service | URL |
|---------|-----|
| Webmail | `https://mail.ugenrobot.com/webmail` |
| Admin Panel | `https://mail.ugenrobot.com/admin` |
| REST API | `https://mail.ugenrobot.com/api` |
| IMAP | `mail.ugenrobot.com:993` (TLS) |
| SMTP Submission | `mail.ugenrobot.com:587` (STARTTLS) |

## Security Notes

- Port 80/443 are handled by Caddy (systemd), not by the Mailu container.
- SMTP/IMAP TLS uses acme.sh DNS-01 challenge -- no port 80 dependency for certificate renewal.
- All mail ports bind to the server private IP (172.25.10.56), not 0.0.0.0, reducing exposure.
- IPv6 is explicitly disabled -- Docker IPv6 has known open relay risks.
- `RELAYNETS` must remain empty. A non-empty relay network allows unauthorized third parties to send mail through this server.
- ClamAV is memory-limited to 1 GB (`mem_limit: 1g` in compose.yaml) to prevent OOM on low-RAM servers.

## Documentation

- [DNS Setup Guide](docs/DNS.md) -- complete DNS records reference and verification for Tencent Cloud DNSPod, including SPF, DKIM, DMARC, MTA-STS, and TLS-RPT.
- [Operations Guide](docs/OPERATIONS.md) -- day-to-day management, backup, log rotation, and troubleshooting (TODO).

## License

This project is a deployment configuration for [Mailu](https://mailu.io/), which is licensed under the MIT License. The deployment scripts and documentation in this repository are provided as-is for reference.
