#!/usr/bin/env bash
#
# preflight.sh — Mailu Email Server Pre-Flight Validation
#
# Performs 10 readiness checks before deploying Mailu. Must pass all
# checks before the deployment should proceed.
#
# Usage: ./preflight.sh
# Exit: 0 if all checks pass, 1 otherwise

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
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

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Mailu Server Pre-Flight Validation                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Check 1: Docker Daemon ─────────────────────────────────────────────
echo " [1/10] Docker Daemon"
if docker info >/dev/null 2>&1; then
    check_result pass "Docker daemon is running"
else
    check_result fail "Docker daemon is NOT running" \
        "Run: sudo systemctl enable --now docker"
fi

# ── Check 2: Docker Compose ────────────────────────────────────────────
echo " [2/10] Docker Compose"
if docker compose version >/dev/null 2>&1; then
    check_result pass "Docker Compose is available"
else
    check_result fail "Docker Compose is NOT available" \
        "Install: sudo apt install docker-compose-plugin"
fi

# ── Check 3: Required Ports Free (25, 465, 587, 993) ───────────────────
echo " [3/10] Required Ports (25, 465, 587, 993)"
all_ports_free=true
occupied_ports=""

for port in 25 465 587 993; do
    if ss -tlnp "sport = :$port" 2>/dev/null | grep -q LISTEN; then
        all_ports_free=false
        occupied_ports="$occupied_ports $port"
    fi
done

if [ "$all_ports_free" = true ]; then
    check_result pass "Ports 25, 465, 587, 993 are all free"
else
    check_result fail "Ports occupied:${occupied_ports}" \
        "Stop the service listening on those ports before deploying Mailu"
fi

# ── Check 4: iptables DOCKER Chain ─────────────────────────────────────
echo " [4/10] iptables DOCKER Chain"
if iptables -L DOCKER -n >/dev/null 2>&1; then
    check_result pass "DOCKER chain exists in iptables"
else
    check_result fail "DOCKER chain NOT found in iptables" \
        "Restart Docker: sudo systemctl restart docker"
fi

# ── Check 5: RAM >= 3.5 GiB ───────────────────────────────────────────
echo " [5/10] System Memory"
total_mib=$(free -m | awk '/Mem:/ {print $2}')
total_gib=$(awk "BEGIN {printf \"%.1f\", $total_mib / 1024}")

if [ "$total_mib" -ge 3584 ]; then
    check_result pass "Total RAM: ${total_gib} GiB (${total_mib} MiB)"
else
    check_result fail "Insufficient RAM: ${total_gib} GiB (${total_mib} MiB)" \
        "Upgrade instance to at least 4 GiB RAM (3.5 GiB minimum)"
fi

# ── Check 6: Disk Space >= 20 GB Free ──────────────────────────────────
echo " [6/10] Disk Space"
free_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

if [ "$free_gb" -ge 20 ]; then
    check_result pass "Free disk space on /: ${free_gb} GB"
else
    check_result fail "Low disk space on /: ${free_gb} GB free" \
        "Free up at least 20 GB on the root filesystem"
fi

# ── Check 7: Swap Configured ───────────────────────────────────────────
echo " [7/10] Swap"
swap_out=$(swapon --show 2>/dev/null)

if [ -n "$swap_out" ]; then
    swap_total=$(echo "$swap_out" | awk 'NR==2 {print $3}' | sed 's/\..*//')
    check_result pass "Swap is configured ($(echo "$swap_out" | awk 'NR==2 {print $3}'))"
else
    check_result fail "No swap configured" \
        "Create swap: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
fi

# ── Check 8: Detect Private IP (BIND_ADDRESS4) ─────────────────────────
echo " [8/10] Private IP Detection"
private_ip=$(ip -4 addr show | grep inet | grep -v 127.0.0.1 \
    | grep -v '172\.17\.0\.' | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -n "$private_ip" ]; then
    check_result pass "Detected private IP: ${private_ip}"
else
    check_result fail "Could not detect private IP" \
        "Verify network interface has a private IPv4 address (excl. 127.0.0.1, 172.17.0.x)"
fi

# ── Check 9: No Existing Postfix / Dovecot ─────────────────────────────
echo " [9/10] Existing Mail Services"
conflicting=false
conflict_list=""

for svc in postfix dovecot; do
    status=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [ "$status" = "active" ]; then
        conflicting=true
        conflict_list="$conflict_list $svc"
    fi
done

if [ "$conflicting" = false ]; then
    check_result pass "No conflicting mail services (Postfix/Dovecot)"
else
    check_result fail "Conflicting service(s) active:${conflict_list}" \
        "Stop them: sudo systemctl stop${conflict_list}"
fi

# ── Check 10: DNS Resolution ───────────────────────────────────────────
echo " [10/10] DNS Resolution"
if host localhost >/dev/null 2>&1; then
    check_result pass "DNS resolution working"
else
    check_result fail "DNS resolution failed" \
        "Check /etc/resolv.conf and network connectivity"
fi

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
total=$((passed + failed))

if [ "$failed" -eq 0 ]; then
    echo -e " ${PASS}  ${passed}/${total} checks passed — ready to deploy"
    exit 0
else
    echo -e " ${FAIL}  ${passed}/${total} checks passed, ${failed} failed"
    echo ""
    echo " Review the FAIL items above and remediate before deploying."
    exit 1
fi
