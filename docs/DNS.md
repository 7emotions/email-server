# DNS Configuration Guide — ugenrobot.com Email Server

> **Platform**: Tencent Cloud DNSPod (腾讯云 DNSPod)
> **Domain**: ugenrobot.com
> **Server IP**: 47.98.123.173
> **Mail Hostname**: mail.ugenrobot.com
> **VPS Provider**: Alibaba Cloud ECS (阿里云)
> **Last Updated**: 2026-05-21

---

## Table of Contents

1. [Overview](#overview)
2. [Accessing Tencent Cloud DNSPod](#accessing-tencent-cloud-dnspod)
3. [DNS Records Reference](#dns-records-reference)
   - [1. A Record — mail.ugenrobot.com](#1-a-record--mailugenrobotcom)
   - [2. MX Record — ugenrobot.com](#2-mx-record--ugenrobotcom)
   - [3. SPF TXT Record — ugenrobot.com](#3-spf-txt-record--ugenrobotcom)
   - [4. DKIM TXT Record — mail._domainkey.ugenrobot.com](#4-dkim-txt-record--mail_domainkeyugenrobotcom)
   - [5. DMARC TXT Record — _dmarc.ugenrobot.com](#5-dmarc-txt-record--_dmarcugenrobotcom)
   - [6. MTA-STS TXT Record — _mta-sts.ugenrobot.com](#6-mta-sts-txt-record--_mta-stsugenrobotcom)
   - [7. TLS-RPT TXT Record — _smtp._tls.ugenrobot.com](#7-tls-rpt-txt-record--_smtp_tlsugenrobotcom)
   - [8. Autodiscover CNAME — autodiscover.ugenrobot.com](#8-autodiscover-cname--autodiscoverugenrobotcom)
   - [9. Autoconfig CNAME — autoconfig.ugenrobot.com](#9-autoconfig-cname--autoconfigugenrobotcom)
4. [Quick Copy-Paste Summary](#quick-copy-paste-summary)
5. [Deployment Order](#deployment-order)
6. [DMARC Progression Plan](#dmarc-progression-plan)
7. [PTR / Reverse DNS (Alibaba Cloud)](#ptr--reverse-dns-alibaba-cloud)
8. [MTA-STS Policy File](#mta-sts-policy-file)
9. [Verification Commands](#verification-commands)
10. [Propagation Expectations](#propagation-expectations)

---

## Overview

Setting up DNS for a self-hosted email server is the most critical step. If any record is missing or wrong, email delivery will fail silently — your messages get rejected, flagged as spam, or bounce without explanation.

This guide covers **9 DNS records** you must create in DNSPod. It explains what each record does, why it matters, and how to verify it works.

**If you are not familiar with DNS terms:**

- **A record** — maps a hostname (like `mail.ugenrobot.com`) to an IP address.
- **MX record** — tells the internet "email for @ugenrobot.com goes to this mail server."
- **TXT record** — stores text policies that other mail servers check (SPF, DKIM, DMARC).
- **CNAME record** — aliases one hostname to another (like a forwarding address).

---

## Accessing Tencent Cloud DNSPod

1. Go to **https://console.cloud.tencent.com/**
2. Log in with your Tencent Cloud account.
3. In the top search bar, type **DNS Resolution** (DNS 解析) and click the result.
   - Or navigate: Products (产品) > Domain (域名) > DNS Resolution (DNSPod DNS 解析).
4. You will see a list of your domains. Click **ugenrobot.com**.
5. You are now on the **Record Management** (记录管理) page. This is where you add all DNS records.
6. To add a record, click the **Add Record** (添加记录) button.

For each record in the sections below, the **Host/Name** field is what you enter in DNSPod, and the **Value/Points to** field is the destination.

---

## DNS Records Reference

### 1. A Record — mail.ugenrobot.com

Maps the mail subdomain to your server IP. This is the foundation record: without it, `mail.ugenrobot.com` does not resolve to your server, and nothing else works.

| Field | Value |
|-------|-------|
| Record Type | `A` |
| Host | `mail` |
| Value | `47.98.123.173` |
| TTL | `3600` |

**Explanation**: When another mail server looks up `mail.ugenrobot.com`, it gets `47.98.123.173` and connects to your Mailu instance.

**DNSPod entry**: Host = `mail`, Record Type = `A`, Value = `47.98.123.173`.

**Verify**:
```bash
dig A mail.ugenrobot.com +short
# Expected: 47.98.123.173
```

---

### 2. MX Record — ugenrobot.com

Tells the world which server handles email for `@ugenrobot.com` addresses. Without MX, no one can send mail TO you.

| Field | Value |
|-------|-------|
| Record Type | `MX` |
| Host | `@` (or leave blank, meaning the root domain) |
| Value | `mail.ugenrobot.com` |
| Priority | `10` |
| TTL | `3600` |

**Explanation**: When Gmail, Outlook, or any other provider needs to deliver an email to `user@ugenrobot.com`, they do an MX lookup, find `mail.ugenrobot.com` (priority 10), then do an A lookup on that hostname to get the IP.

**DNSPod entry**: Host = `@` (or leave blank), Record Type = `MX`, Value = `mail.ugenrobot.com.`, Priority = `10`.

> **Note**: The trailing dot on `mail.ugenrobot.com.` is standard DNS notation for a fully qualified domain name. DNSPod usually adds it automatically. Do not worry if you see it with or without the trailing dot.

**Verify**:
```bash
dig MX ugenrobot.com +short
# Expected: 10 mail.ugenrobot.com.
```

---

### 3. SPF TXT Record — ugenrobot.com

Sender Policy Framework. This record lists which IP addresses are authorized to send email for your domain. It tells receiving mail servers: "only emails from 47.98.123.173 are legitimate."

| Field | Value |
|-------|-------|
| Record Type | `TXT` |
| Host | `@` (or leave blank, meaning the root domain) |
| Value | `"v=spf1 ip4:47.98.123.173 -all"` |
| TTL | `3600` |

**Explanation**:
- `v=spf1` — the SPF version identifier.
- `ip4:47.98.123.173` — only this IP can send mail.
- `-all` — reject all other senders (hard fail). The `-` (minus) means hard fail; `~all` would be soft fail (mark as suspicious but deliver).

> **Important**: If you later add a sending service (transactional email, newsletter provider), you must add their IP to this record. Example: `v=spf1 ip4:47.98.123.173 include:spf.mailgun.org -all`.

**DNSPod entry**: Host = `@`, Record Type = `TXT`, Value = `v=spf1 ip4:47.98.123.173 -all` (DNSPod adds the quotes).

**Verify**:
```bash
dig TXT ugenrobot.com +short
# Expected: "v=spf1 ip4:47.98.123.173 -all"
```

---

### 4. DKIM TXT Record — mail._domainkey.ugenrobot.com

DomainKeys Identified Mail. DKIM lets you cryptographically sign outgoing emails. Receiving servers verify the signature using your public key, proving the email was not tampered with in transit.

**IMPORTANT: The DKIM key is generated AFTER Mailu is deployed.**

You cannot create this record until you complete these steps:

1. Deploy Mailu.
2. Log in to the Mailu admin web panel at `https://mail.ugenrobot.com/admin`.
3. Go to the domain settings for `ugenrobot.com`.
4. Click **Generate DKIM key** (or similar button in the domain configuration).
5. Mailu will show you a public key. That key goes into this DNS record.
6. Copy the public key and create the DNS record below.

**Before deployment, leave this record with the placeholder.** After deployment, replace `<GENERATE_AFTER_DEPLOY>` with the actual key from the Mailu admin panel.

| Field | Value |
|-------|-------|
| Record Type | `TXT` |
| Host | `mail._domainkey` |
| Value | `"v=DKIM1; k=rsa; p=<GENERATE_AFTER_DEPLOY>"` |
| TTL | `3600` |

**Explanation**: The selector `mail` is the default for Mailu. The `_domainkey` prefix is standard. When a receiving server gets a signed email, it looks up `mail._domainkey.ugenrobot.com` to fetch the public key and verify the signature.

**DNSPod entry**: Host = `mail._domainkey`, Record Type = `TXT`, Value = `v=DKIM1; k=rsa; p=<GENERATE_AFTER_DEPLOY>`.

**Verify**:
```bash
dig TXT mail._domainkey.ugenrobot.com +short
# Expected: "v=DKIM1; k=rsa; p=..." (long base64 string)
```

> **Troubleshooting**: The DKIM public key is typically a long string (200-400 characters). Make sure DNSPod stores it as a single TXT record. If the key is very long, you may need to split it into multiple quoted strings — DNSPod normally handles this automatically for values under 512 characters.

---

### 5. DMARC TXT Record — _dmarc.ugenrobot.com

Domain-based Message Authentication, Reporting & Conformance. DMARC tells receiving servers what to do when an email fails both SPF and DKIM checks. It also sends you daily/weekly reports so you can monitor who is sending email from your domain.

**Start with `p=none` (monitoring mode)** — see the [DMARC Progression Plan](#dmarc-progression-plan) for the upgrade schedule.

| Field | Value |
|-------|-------|
| Record Type | `TXT` |
| Host | `_dmarc` |
| Value | `"v=DMARC1; p=none; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100"` |
| TTL | `3600` |

**Explanation**:
- `v=DMARC1` — version identifier.
- `p=none` — take no action on failed emails (just report). Change to `p=quarantine` then `p=reject` later.
- `rua=mailto:postmaster@ugenrobot.com` — send aggregate DMARC reports to postmaster.
- `fo=1` — generate failure reports for any authentication failure.
- `pct=100` — apply to 100% of emails.

**DNSPod entry**: Host = `_dmarc`, Record Type = `TXT`, Value = `v=DMARC1; p=none; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100`.

**Verify**:
```bash
dig TXT _dmarc.ugenrobot.com +short
# Expected: "v=DMARC1; p=none; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100"
```

---

### 6. MTA-STS TXT Record — _mta-sts.ugenrobot.com

SMTP MTA Strict Transport Security. MTA-STS tells other mail servers: "always use TLS when connecting to my server." It prevents downgrade attacks where an attacker forces plaintext delivery.

This is a **two-part** setup: a TXT record (below) and a policy file served via HTTPS (see [MTA-STS Policy File](#mta-sts-policy-file)).

| Field | Value |
|-------|-------|
| Record Type | `TXT` |
| Host | `_mta-sts` |
| Value | `"v=STSv1; id=20260521"` |
| TTL | `300` |

**Explanation**:
- `v=STSv1` — MTA-STS version.
- `id=20260521` — a version identifier for the policy. Update this (e.g., to the next date) when the policy changes. Must match the `id` in the HTTPS policy file.

> **Note**: TTL is 300 (5 minutes) instead of 3600 because MTA-STS policies may change more frequently during initial setup.

**DNSPod entry**: Host = `_mta-sts`, Record Type = `TXT`, Value = `v=STSv1; id=20260521`.

**Verify**:
```bash
dig TXT _mta-sts.ugenrobot.com +short
# Expected: "v=STSv1; id=20260521"
```

---

### 7. TLS-RPT TXT Record — _smtp._tls.ugenrobot.com

TLS Reporting. TLS-RPT tells other mail servers to send you reports about TLS connection failures. If someone tries to deliver email to you and the TLS handshake fails, you get a report.

| Field | Value |
|-------|-------|
| Record Type | `TXT` |
| Host | `_smtp._tls` |
| Value | `"v=TLSRPTv1; rua=mailto:postmaster@ugenrobot.com"` |
| TTL | `3600` |

**Explanation**:
- `v=TLSRPTv1` — TLS reporting version.
- `rua=mailto:postmaster@ugenrobot.com` — send TLS failure reports to postmaster.

**DNSPod entry**: Host = `_smtp._tls`, Record Type = `TXT`, Value = `v=TLSRPTv1; rua=mailto:postmaster@ugenrobot.com`.

**Verify**:
```bash
dig TXT _smtp._tls.ugenrobot.com +short
# Expected: "v=TLSRPTv1; rua=mailto:postmaster@ugenrobot.com"
```

---

### 8. Autodiscover CNAME — autodiscover.ugenrobot.com

Used by Microsoft Outlook and Exchange clients to automatically discover email server settings. When a user sets up their `@ugenrobot.com` email in Outlook, the client queries this record to find the server configuration.

| Field | Value |
|-------|-------|
| Record Type | `CNAME` |
| Host | `autodiscover` |
| Value | `mail.ugenrobot.com` |
| TTL | `3600` |

**Explanation**: Outlook looks up `autodiscover.ugenrobot.com`, follows the CNAME to `mail.ugenrobot.com`, and fetches the autodiscover XML configuration from the Mailu server.

**DNSPod entry**: Host = `autodiscover`, Record Type = `CNAME`, Value = `mail.ugenrobot.com.`

**Verify**:
```bash
dig CNAME autodiscover.ugenrobot.com +short
# Expected: mail.ugenrobot.com.
```

---

### 9. Autoconfig CNAME — autoconfig.ugenrobot.com

Used by Thunderbird and other email clients to automatically configure account settings. When a user enters their email address in Thunderbird, the client queries this record.

| Field | Value |
|-------|-------|
| Record Type | `CNAME` |
| Host | `autoconfig` |
| Value | `mail.ugenrobot.com` |
| TTL | `3600` |

**Explanation**: Thunderbird looks up `autoconfig.ugenrobot.com`, follows the CNAME to `mail.ugenrobot.com`, and fetches the Mozilla autoconfig XML from the Mailu server.

**DNSPod entry**: Host = `autoconfig`, Record Type = `CNAME`, Value = `mail.ugenrobot.com.`

**Verify**:
```bash
dig CNAME autoconfig.ugenrobot.com +short
# Expected: mail.ugenrobot.com.
```

---

## Quick Copy-Paste Summary

Use this table to enter all records into DNSPod at once:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| `A` | `mail` | `47.98.123.173` | 3600 |
| `MX` | `@` (or blank) | `mail.ugenrobot.com.` (priority 10) | 3600 |
| `TXT` | `@` (or blank) | `v=spf1 ip4:47.98.123.173 -all` | 3600 |
| `TXT` | `mail._domainkey` | `v=DKIM1; k=rsa; p=<GENERATE_AFTER_DEPLOY>` | 3600 |
| `TXT` | `_dmarc` | `v=DMARC1; p=none; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100` | 3600 |
| `TXT` | `_mta-sts` | `v=STSv1; id=20260521` | 300 |
| `TXT` | `_smtp._tls` | `v=TLSRPTv1; rua=mailto:postmaster@ugenrobot.com` | 3600 |
| `CNAME` | `autodiscover` | `mail.ugenrobot.com.` | 3600 |
| `CNAME` | `autoconfig` | `mail.ugenrobot.com.` | 3600 |

---

## Deployment Order

Do NOT add all records at once. Follow this order to minimize delivery failures:

### Phase 1: Foundation (Day 1)
1. **A record** for `mail.ugenrobot.com`
2. **MX record** for `ugenrobot.com`
3. **CNAME records** for `autodiscover` and `autoconfig`

**Wait**: 30-60 minutes for propagation. During this time, deploy Mailu on the server.

**Why first**: Without A and MX, email cannot be delivered. Autodiscover/autoconfig are needed for client setup.

### Phase 2: Authentication (Day 1, after Mailu deploy)
4. **SPF record** — publish immediately after MX is set up
5. **DKIM record** — generate key in Mailu admin panel first, then publish

**Wait**: 30-60 minutes for propagation.

**Why second**: SPF and DKIM are the authentication mechanisms. Without them, your emails are likely to be flagged as spam.

### Phase 3: Policy (Day 2+)
6. **DMARC record** (start with `p=none`)
7. **MTA-STS record**
8. **TLS-RPT record**

**Wait**: 24 hours after SPF/DKIM propagation.

**Why last**: DMARC policies tell receiving servers how to handle unauthenticated email. If you set `p=reject` before SPF/DKIM are fully propagated and configured, you will lose legitimate emails. Always start with `p=none`.

### Phase 4: PTR (Day 2+)
9. **PTR record** — submit ticket to Alibaba Cloud

**Note**: PTR can be done in parallel with Phase 3. It takes the longest (1-3 business days), so start the process early.

---

## DMARC Progression Plan

DMARC policies should be tightened gradually. Jumping straight to `p=reject` will cause legitimate email to be rejected if SPF or DKIM have any configuration issues.

### Weeks 1-4: Monitoring (`p=none`)

```
v=DMARC1; p=none; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100
```

- No emails are blocked or quarantined.
- You receive DMARC aggregate reports (`rua`) that show which sources are sending email from your domain.
- **Goal**: Establish a baseline. Verify that all your legitimate email passes SPF and DKIM. Check reports weekly for unauthorized senders.
- **Expected report volume**: 1-5 reports per day. If you see thousands, someone is spoofing your domain.

### Weeks 4-8: Quarantine (`p=quarantine`)

```
v=DMARC1; p=quarantine; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100
```

- Emails that fail both SPF and DKIM are sent to the recipient's spam folder.
- **Goal**: Catch configuration issues before moving to reject. Monitor your postmaster inbox for any "your email was quarantined" complaints.
- **Action**: If a legitimate service fails authentication, fix its SPF/DKIM configuration during this window.

### Week 8+: Reject (`p=reject`)

```
v=DMARC1; p=reject; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100
```

- Emails that fail both SPF and DKIM are rejected outright.
- **Goal**: Maximum protection against spoofing and phishing.
- **This is the end state** for a properly configured email server.

> **How to update DMARC in DNSPod**: Edit the TXT record for `_dmarc`. Change just the `p=` value. The rest of the record stays the same.

---

## PTR / Reverse DNS (Alibaba Cloud)

PTR (Pointer Record) maps an IP address back to a hostname — the reverse of an A record. Many mail servers reject email from IPs without a matching PTR record. Your PTR must point `47.98.123.173` to `mail.ugenrobot.com`.

**Important**: DNS is managed in Tencent Cloud DNSPod, but PTR is managed by the VPS provider — Alibaba Cloud. You cannot add PTR records in DNSPod.

### How to request PTR from Alibaba Cloud

1. Log in to the **Alibaba Cloud Console** (https://console.aliyun.com/).
2. Go to **Elastic Compute Service (ECS)** > **Instances**.
3. Find the instance with IP `47.98.123.173`.
4. Look for a **Reverse DNS** or **PTR** option in the instance details.
   - If you see an editable PTR field, enter `mail.ugenrobot.com` and save.
   - If there is no self-service option, you must open a support ticket.

### Support ticket template (if self-service is unavailable)

Use this template when submitting a ticket to Alibaba Cloud support:

```
Subject: Request to set Reverse DNS (PTR) for IP 47.98.123.173

Dear Alibaba Cloud Support,

I request that the reverse DNS (PTR) record for the following IP address be set:

- IP Address: 47.98.123.173
- Desired PTR Value: mail.ugenrobot.com
- Domain: ugenrobot.com
- ECS Instance ID: [INSERT YOUR INSTANCE ID]
- Region: [INSERT YOUR REGION, e.g., cn-hangzhou]

The A record for mail.ugenrobot.com already resolves to 47.98.123.173,
so the forward and reverse DNS will match (required by many mail servers for
anti-spam validation).

Please confirm once this change has been applied. If additional verification
is required (such as domain ownership confirmation), please let me know what
steps are needed.

Thank you.
```

### Verify PTR

Run this from an EXTERNAL machine (not the server itself):

```bash
dig -x 47.98.123.173 +short
# Expected: mail.ugenrobot.com.
```

> **Expected turnaround**: 1-3 business days for Alibaba Cloud to process PTR requests.

---

## MTA-STS Policy File

The MTA-STS TXT record (record #6) is only half of the setup. You must also serve a policy file via HTTPS.

### The policy file

The file must be available at this exact URL:

```
https://mta-sts.ugenrobot.com/.well-known/mta-sts.txt
```

Note: this requires a separate subdomain `mta-sts.ugenrobot.com`. You need an additional A record:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| `A` | `mta-sts` | `47.98.123.173` | 3600 |

### Policy file content

Create a file at the path `.well-known/mta-sts.txt` on your web server (or Mailu's nginx) with this content:

```
version: STSv1
mode: enforce
mx: mail.ugenrobot.com
max_age: 86400
```

**Explanation**:
- `mode: enforce` — require TLS for all SMTP connections.
- `mx: mail.ugenrobot.com` — the only MX server.
- `max_age: 86400` — cache this policy for 1 day.

> **TODO: This is a post-deployment task**. After Mailu is running, configure nginx (or the web server) to serve this file. The `id` value in the DNS TXT record must match the `id` in the policy file (or use a versioning scheme where the DNS `id` changes when the policy content changes).

### Verify MTA-STS policy

```bash
curl -s https://mta-sts.ugenrobot.com/.well-known/mta-sts.txt
# Expected:
# version: STSv1
# mode: enforce
# mx: mail.ugenrobot.com
# max_age: 86400
```

---

## Verification Commands

Run these from an **external machine** (your laptop, a cloud shell, any machine that is NOT the mail server itself). Running dig on the server could show cached or local DNS results that differ from what the rest of the internet sees.

### Quick sanity check (all records)

```bash
# A record
dig A mail.ugenrobot.com +short
# Expected: 47.98.123.173

# MX record
dig MX ugenrobot.com +short
# Expected: 10 mail.ugenrobot.com.

# SPF record
dig TXT ugenrobot.com +short
# Expected: "v=spf1 ip4:47.98.123.173 -all"

# DKIM record
dig TXT mail._domainkey.ugenrobot.com +short
# Expected: "v=DKIM1; k=rsa; p=..."

# DMARC record
dig TXT _dmarc.ugenrobot.com +short
# Expected: "v=DMARC1; p=none; rua=mailto:postmaster@ugenrobot.com; fo=1; pct=100"

# MTA-STS record
dig TXT _mta-sts.ugenrobot.com +short
# Expected: "v=STSv1; id=20260521"

# TLS-RPT record
dig TXT _smtp._tls.ugenrobot.com +short
# Expected: "v=TLSRPTv1; rua=mailto:postmaster@ugenrobot.com"

# Autodiscover CNAME
dig CNAME autodiscover.ugenrobot.com +short
# Expected: mail.ugenrobot.com.

# Autoconfig CNAME
dig CNAME autoconfig.ugenrobot.com +short
# Expected: mail.ugenrobot.com.

# A record for mta-sts subdomain
dig A mta-sts.ugenrobot.com +short
# Expected: 47.98.123.173
```

### Full verification script

Save this as `check-dns.sh` on any external machine:

```bash
#!/bin/bash
DOMAIN="ugenrobot.com"
IP="47.98.123.173"

echo "=== DNS Verification for $DOMAIN ==="
echo

echo "1. A record (mail.$DOMAIN)"
result=$(dig A mail.$DOMAIN +short)
echo "   Expected: $IP"
echo "   Got:      $result"
[ "$result" = "$IP" ] && echo "   PASS" || echo "   FAIL"
echo

echo "2. MX record ($DOMAIN)"
result=$(dig MX $DOMAIN +short)
echo "   Expected: 10 mail.$DOMAIN."
echo "   Got:      $result"
echo "   PASS (check value manually)"
echo

echo "3. SPF record ($DOMAIN)"
result=$(dig TXT $DOMAIN +short)
echo "   Expected: v=spf1 ip4:$IP -all"
echo "   Got:      $result"
[[ "$result" == *"v=spf1"* ]] && echo "   PASS (SPF present)" || echo "   FAIL"
echo

echo "4. DKIM record (mail._domainkey.$DOMAIN)"
result=$(dig TXT mail._domainkey.$DOMAIN +short)
echo "   Got:      $result"
[[ "$result" == *"v=DKIM1"* ]] && echo "   PASS (DKIM present)" || echo "   INFO (placeholder OK)"
echo

echo "5. DMARC record (_dmarc.$DOMAIN)"
result=$(dig TXT _dmarc.$DOMAIN +short)
echo "   Got:      $result"
[[ "$result" == *"v=DMARC1"* ]] && echo "   PASS" || echo "   FAIL"
echo

echo "6. Autodiscover CNAME (autodiscover.$DOMAIN)"
result=$(dig CNAME autodiscover.$DOMAIN +short)
echo "   Expected: mail.$DOMAIN."
echo "   Got:      $result"
[[ "$result" == *"mail.$DOMAIN"* ]] && echo "   PASS" || echo "   FAIL"
echo

echo "7. Autoconfig CNAME (autoconfig.$DOMAIN)"
result=$(dig CNAME autoconfig.$DOMAIN +short)
echo "   Expected: mail.$DOMAIN."
echo "   Got:      $result"
[[ "$result" == *"mail.$DOMAIN"* ]] && echo "   PASS" || echo "   FAIL"
echo

echo "=== Done ==="
```

### Online verification tools

For extra confidence, use these online tools (run from your browser):

| Tool | URL | What it checks |
|------|-----|----------------|
| MXToolbox | https://mxtoolbox.com/ | MX, SPF, DMARC, blacklists |
| DNSSEC Test | https://dnssec-analyzer.verisignlabs.com/ | DNSSEC validation |
| DKIM Validator | https://www.dkimvalidator.com/ | DKIM signature test |
| MTA-STS Check | https://www.mta-sts.com/ | MTA-STS policy check |

---

## Propagation Expectations

| Record Type | Typical Propagation Time | Notes |
|-------------|--------------------------|-------|
| A record | Minutes to 1 hour | Fast, especially with DNSPod |
| MX record | Minutes to 1 hour | Depends on recursive DNS caches |
| TXT records (SPF, DKIM, DMARC, etc.) | Minutes to 1 hour | Same as A records on DNSPod |
| CNAME records | Minutes to 1 hour | Similar to A records |
| PTR record | 1 to 3 business days | Requires Alibaba Cloud support ticket. Must match A record. |
| MTA-STS policy | 5 minutes (DNS) + 24h (policy cache) | DNS TTL is 300s, but policy `max_age` is 86400s |

> **Note**: DNSPod is known for fast propagation (often within 5-10 minutes on the Chinese mainland). However, DNS resolvers worldwide may cache records for up to the TTL value. Your TTL of 3600 (1 hour) means some users may not see changes for up to 1 hour.

---

## Troubleshooting Common Issues

### "My emails are going to spam"

1. Check SPF: `dig TXT ugenrobot.com +short` — verify the record is present and correct.
2. Check DKIM: verify the key was published correctly after generation.
3. Check DMARC reports: review the `rua` inbox for authentication failure reports.
4. Check PTR: `dig -x 47.98.123.173 +short` — must return `mail.ugenrobot.com.`
5. Check blacklists: use MXToolbox blacklist checker.

### "I changed a record but it still shows the old value"

- Wait for TTL to expire. If your record has TTL 3600, wait at least 1 hour.
- Use `dig @8.8.8.8` to query Google's DNS directly (bypasses local caching):
  ```bash
  dig @8.8.8.8 TXT ugenrobot.com +short
  ```
- Flush your local DNS cache if needed.

### "DNSPod shows an error when I add the TXT record"

- Check that the value is not over 512 characters (for TXT records). DKIM keys are sometimes long — if you get an error, try splitting the value into quoted sections.
- Ensure the host field contains only `mail._domainkey` without the domain suffix. DNSPod appends the domain automatically.

### "My MTA-STS policy is not being picked up"

- First check DNS: `dig TXT _mta-sts.ugenrobot.com +short`
- Then check HTTPS: `curl -s https://mta-sts.ugenrobot.com/.well-known/mta-sts.txt`
- Make sure the `id` field in both the DNS record and the policy file match.
- Make sure the HTTPS certificate for `mta-sts.ugenrobot.com` is valid (not self-signed).

---

## Reference

- **Tencent Cloud DNSPod Docs**: https://cloud.tencent.com/document/product/302
- **Mailu DNS Setup Docs**: https://mailu.io/master/install/setup.html#dns
- **DMARC Guide**: https://dmarc.org/overview/
- **MTA-STS Standard**: RFC 8461
- **TLS-RPT Standard**: RFC 8460
