#!/usr/bin/env bash
#
# preflight.sh — Stalwart Email Server Pre-Flight Validation
#
# Performs 8 readiness checks before deploying Stalwart. Must pass all
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
echo "║       Stalwart Server Pre-Flight Validation                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Check 1: Docker Daemon ─────────────────────────────────────────────
echo " [1/8] Docker Daemon"
if docker info >/dev/null 2>&1; then
    check_result pass "Docker daemon is running"
else
    check_result fail "Docker daemon is NOT running" \
        "Run: sudo systemctl enable --now docker"
fi

# ── Check 2: Docker Compose ────────────────────────────────────────────
echo " [2/8] Docker Compose"
if docker compose version >/dev/null 2>&1; then
    check_result pass "Docker Compose is available"
else
    check_result fail "Docker Compose is NOT available" \
        "Install: sudo apt install docker-compose-plugin"
fi

# ── Check 3: Required Ports Free (25, 465, 587, 993, 8080) ─────────────
echo " [3/8] Required Ports (25, 465, 587, 993, 8080)"
all_ports_free=true
occupied_ports=""

for port in 25 465 587 993 8080; do
    if ss -tlnp "sport = :$port" 2>/dev/null | grep -q LISTEN; then
        all_ports_free=false
        occupied_ports="$occupied_ports $port"
    fi
done

if [ "$all_ports_free" = true ]; then
    check_result pass "Ports 25, 465, 587, 993, 8080 are all free"
else
    check_result fail "Ports occupied:${occupied_ports}" \
        "Stop the service listening on those ports before deploying Stalwart"
fi

# ── Check 4: iptables DOCKER Chain ─────────────────────────────────────
echo " [4/8] iptables DOCKER Chain"
if iptables -L DOCKER -n >/dev/null 2>&1; then
    check_result pass "DOCKER chain exists in iptables"
else
    check_result fail "DOCKER chain NOT found in iptables" \
        "Restart Docker: sudo systemctl restart docker"
fi

# ── Check 5: RAM >= 1.0 GiB ────────────────────────────────────────────
echo " [5/8] System Memory"
total_mib=$(free -m | awk '/Mem:/ {print $2}')
total_gib=$(awk "BEGIN {printf \"%.1f\", $total_mib / 1024}")

if [ "$total_mib" -ge 1024 ]; then
    check_result pass "Total RAM: ${total_gib} GiB (${total_mib} MiB)"
else
    check_result fail "Insufficient RAM: ${total_gib} GiB (${total_mib} MiB)" \
        "Upgrade instance to at least 1 GiB RAM"
fi

# ── Check 6: Disk Space >= 20 GB Free ──────────────────────────────────
echo " [6/8] Disk Space"
free_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

if [ "$free_gb" -ge 20 ]; then
    check_result pass "Free disk space on /: ${free_gb} GB"
else
    check_result fail "Low disk space on /: ${free_gb} GB free" \
        "Free up at least 20 GB on the root filesystem"
fi

# ── Check 7: Swap Configured ───────────────────────────────────────────
echo " [7/8] Swap"
swap_out=$(swapon --show 2>/dev/null)

if [ -n "$swap_out" ]; then
    swap_total=$(echo "$swap_out" | awk 'NR==2 {print $3}' | sed 's/\..*//')
    check_result pass "Swap is configured ($(echo "$swap_out" | awk 'NR==2 {print $3}'))"
else
    check_result fail "No swap configured" \
        "Create swap: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
fi

# ── Check 8: DNS Resolution ────────────────────────────────────────────
echo " [8/8] DNS Resolution"
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
