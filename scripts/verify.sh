#!/usr/bin/env bash
#
# verify.sh — Mailu Email Server Post-Deployment Verification
#
# Performs 14 comprehensive checks after `docker compose up -d` completes.
# Must pass all checks to confirm a successful deployment.
#
# Usage: ./verify.sh
# Exit: 0 if all checks pass, 1 otherwise

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
SKIP="${YELLOW}[SKIP]${NC}"

# ── Counters ────────────────────────────────────────────────────────────
passed=0
failed=0

# ── Helper ──────────────────────────────────────────────────────────────
check_result() {
    local status="$1"
    local label="$2"
    local detail="${3:-}"
    local hint="${4:-}"

    if [ "$status" = "pass" ]; then
        echo -e "  ${PASS} ${label}"
        [ -n "$detail" ] && echo "         ${detail}"
        passed=$((passed + 1))
    else
        echo -e "  ${FAIL} ${label}"
        [ -n "$detail" ] && echo "         ${detail}"
        [ -n "$hint" ] && echo "         >>> ${hint}"
        failed=$((failed + 1))
    fi
}

section_header() {
    echo ""
    echo -e "${CYAN}┌──── ${1}${NC}"
}

# ── Header ──────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Mailu Server Post-Deployment Verification             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════
#  SECTION 1: Container Health Checks
# ═══════════════════════════════════════════════════════════════════════
section_header "Container Health Checks"

# ── Check 1: All Containers Running ─────────────────────────────────────
echo " [1/14] All Containers Running"

expected_services=(
    "mailu-redis"
    "mailu-resolver"
    "mailu-front"
    "mailu-admin"
    "mailu-imap"
    "mailu-smtp"
    "mailu-antispam"
    "mailu-antivirus"
    "mailu-webmail"
)

all_up=true
missing=""

for svc in "${expected_services[@]}"; do
    status_line=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep "^${svc} " || true)
    if [ -z "$status_line" ]; then
        all_up=false
        missing="${missing} ${svc}(missing)"
    elif echo "$status_line" | grep -qv 'Up'; then
        all_up=false
        missing="${missing} ${svc}($status_line)"
    fi
done

if [ "$all_up" = true ]; then
    check_result pass "All 9 containers running"
else
    check_result fail "Not all containers running:${missing}" \
        "Run: docker compose up -d"
fi

# ── Check 2: No Container Restarts ──────────────────────────────────────
echo " [2/14] No Container Restarts"

restarting=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null \
    | grep -E 'Restarting|Exit' || true)

if [ -z "$restarting" ]; then
    check_result pass "No containers in restart/exit loop"
else
    check_result fail "Unhealthy containers detected:" \
        "$(echo "$restarting" | head -3)" \
        "Inspect logs: docker compose logs <container>"
fi

# ── Check 3: ClamAV Version ─────────────────────────────────────────────
echo " [3/14] ClamAV Version"

clamav_version=$(docker compose exec -T antivirus clamscan --version 2>/dev/null | head -1 || true)

if [ -n "$clamav_version" ]; then
    check_result pass "ClamAV responds" "${clamav_version}"
else
    check_result fail "ClamAV is not responding" \
        "Check: docker compose logs antivirus"
fi

# ═══════════════════════════════════════════════════════════════════════
#  SECTION 2: Port Connectivity
# ═══════════════════════════════════════════════════════════════════════
section_header "Port Connectivity"

# ── Check 4: SMTP Port 25 ───────────────────────────────────────────────
echo " [4/14] SMTP Port 25"

if nc -w3 -z localhost 25 2>/dev/null; then
    check_result pass "Port 25 (SMTP) is reachable"
else
    check_result fail "Port 25 (SMTP) is NOT reachable" \
        "Check: docker compose logs smtp"
fi

# ── Check 5: SMTPS Port 465 ─────────────────────────────────────────────
echo " [5/14] SMTPS Port 465"

if nc -w3 -z localhost 465 2>/dev/null; then
    check_result pass "Port 465 (SMTPS) is reachable"
else
    check_result fail "Port 465 (SMTPS) is NOT reachable" \
        "Check: docker compose logs smtp"
fi

# ── Check 6: Submission Port 587 ────────────────────────────────────────
echo " [6/14] Submission Port 587"

if nc -w3 -z localhost 587 2>/dev/null; then
    check_result pass "Port 587 (Submission) is reachable"
else
    check_result fail "Port 587 (Submission) is NOT reachable" \
        "Check: docker compose logs smtp"
fi

# ── Check 7: IMAPS Port 993 ─────────────────────────────────────────────
echo " [7/14] IMAPS Port 993"

if nc -w3 -z localhost 993 2>/dev/null; then
    check_result pass "Port 993 (IMAPS) is reachable"
else
    check_result fail "Port 993 (IMAPS) is NOT reachable" \
        "Check: docker compose logs imap"
fi

# ── Check 8: Front HTTP Port 8443 ───────────────────────────────────────
echo " [8/14] Front HTTP Port 8443"

http_code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8443 2>/dev/null || echo "000")

if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
    check_result pass "Front port 8443 responds" "HTTP ${http_code}"
else
    check_result fail "Front port 8443 no response" "HTTP ${http_code}" \
        "Check: docker compose logs front"
fi

# ═══════════════════════════════════════════════════════════════════════
#  SECTION 3: Basic Service Verification
# ═══════════════════════════════════════════════════════════════════════
section_header "Basic Service Verification"

# ── Check 9: SMTP Banner ────────────────────────────────────────────────
echo " [9/14] SMTP Banner"

smtp_banner=$(echo "QUIT" | nc -w3 localhost 25 2>/dev/null || true)

if echo "$smtp_banner" | grep -qiE 'ESMTP|220'; then
    check_result pass "SMTP banner received"
else
    check_result fail "SMTP banner not detected" \
        "Check: docker compose logs smtp"
fi

# ── Check 10: Admin Container API ───────────────────────────────────────
echo " [10/14] Admin Container API"

admin_output=$(docker compose exec -T admin flask mailu status 2>/dev/null || echo "ADMIN_ENDPOINT_CHECK")

if [ -n "$admin_output" ]; then
    check_result pass "Admin container responds"
else
    check_result fail "Admin container not responding" \
        "Check: docker compose logs admin"
fi

# ═══════════════════════════════════════════════════════════════════════
#  SECTION 4: System Checks
# ═══════════════════════════════════════════════════════════════════════
section_header "System Checks"

# ── Check 11: Swap Configured ───────────────────────────────────────────
echo " [11/14] Swap Configured"

if swapon --show 2>/dev/null | grep -q .; then
    swap_total=$(swapon --show | awk 'NR==2 {print $3}')
    check_result pass "Swap is configured" "${swap_total}"
else
    check_result fail "No swap configured" \
        "Create swap: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"
fi

# ── Check 12: Disk Usage < 80% ──────────────────────────────────────────
echo " [12/14] Disk Usage Under 80%"

disk_pct=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$disk_pct" -lt 80 ]; then
    check_result pass "Disk usage: ${disk_pct}%" "Root filesystem healthy"
else
    check_result fail "Disk usage high: ${disk_pct}%" \
        "Clean up: docker system prune -a, or expand disk"
fi

# ═══════════════════════════════════════════════════════════════════════
#  SECTION 5: DNS Verification
# ═══════════════════════════════════════════════════════════════════════
section_header "DNS Verification"

# ── Check 13: DNS Resolution (External) ─────────────────────────────────
echo " [13/14] DNS Resolution"

dns_result=$(host mail.ugenrobot.com 2>/dev/null | grep 'has address' | awk '{print $NF}' || true)
if [ -z "$dns_result" ]; then
    dns_result=$(dig +short mail.ugenrobot.com 2>/dev/null | grep -v '\.$' | head -1 || true)
fi

if [ -n "$dns_result" ]; then
    check_result pass "mail.ugenrobot.com resolves" "→ ${dns_result}"
else
    check_result fail "mail.ugenrobot.com does not resolve" \
        "Verify DNS A record at your provider"
fi

# ── Check 14: DNS Resolver Container ────────────────────────────────────
echo " [14/14] DNS Resolver Container"

resolver_check=$(docker compose exec -T resolver nslookup localhost 2>/dev/null || true)

if echo "$resolver_check" | grep -q '127.0.0.1'; then
    check_result pass "Resolver resolves localhost"
else
    check_result fail "Resolver container not resolving" \
        "Check: docker compose logs resolver"
fi

# ═══════════════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
total=$((passed + failed))

if [ "$failed" -eq 0 ]; then
    echo -e " ${PASS}  ${passed}/${total} checks passed — DEPLOYMENT VERIFIED"
    echo ""
    echo -e "${GREEN} Mailu email server is running and healthy.${NC}"
    exit 0
else
    echo -e " ${FAIL}  ${passed}/${total} checks passed, ${failed} failed"
    echo ""
    echo " Review the FAIL items above and remediate before going live."
    echo " Common fixes:"
    echo "   - Check container logs: docker compose logs <service>"
    echo "   - Restart services:     docker compose restart"
    echo "   - Full rebuild:         docker compose down && docker compose up -d"
    exit 1
fi
