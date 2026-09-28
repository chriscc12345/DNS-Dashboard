#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# NetFortress Firewall Appliance - Standalone Installer
#
# Deployment option 3: install ONLY the NetFortress Firewall Appliance.
# Nothing else - no Management Portal, no Technitium, no PostgreSQL.
#
# The appliance source ships in appliance/netfortress-appliance.tar.gz;
# its own installer performs the complete setup:
#
#   - NetFortress backend API + web console on port 8080
#   - dnsmasq DNS, Kea DHCP, Squid proxy, blocklists, GeoIP
#   - Guarded transaction tooling (iptables/dns/hostname)
#   - Enforcement reconciler, block page and captive portal rendered
#     automatically by the appliance's own services
#
# Licensing:
#   - The 60-day full-feature trial starts automatically
#   - When the trial runs out the appliance continues automatically
#     on the free Home Lite licence
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLIANCE_ARCHIVE="$SCRIPT_DIR/appliance/netfortress-appliance.tar.gz"
APPLIANCE_SOURCE_DIR="/opt/firewall-appliance-src/firewall-appliance"
APPLIANCE_INSTALLER="$APPLIANCE_SOURCE_DIR/deploy/install.sh"

log() {
    echo
    echo "======================================================================"
    echo "$1"
    echo "======================================================================"
}

ok() {
    echo "[ OK ] $1"
}

warn() {
    echo "[WARN] $1"
}

fail() {
    echo "[ERROR] $1" >&2
    exit 1
}

###############################################################################
# Root + OS checks
###############################################################################

if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this installer as root."
fi

log "SYSTEM CHECK"

if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release not found."
fi

. /etc/os-release

if [[ "${ID}" != "debian" ]]; then
    fail "This installer requires Debian."
fi

if [[ "${VERSION_ID%%.*}" != "13" ]]; then
    fail "This installer requires Debian 13."
fi

ok "Debian ${VERSION_ID}"

###############################################################################
# Installer package check
###############################################################################

log "INSTALLER PACKAGE CHECK"

[[ -f "$APPLIANCE_ARCHIVE" ]] || fail "NetFortress appliance archive not found: $APPLIANCE_ARCHIVE"

ok "NetFortress appliance archive found"

###############################################################################
# Extract the appliance source
###############################################################################

log "EXTRACTING NETFORTRESS APPLIANCE SOURCE"

EXTRACT_ROOT="/opt/firewall-appliance-src"

rm -rf "$EXTRACT_ROOT"
mkdir -p "$EXTRACT_ROOT"

tar -xzf "$APPLIANCE_ARCHIVE" -C "$EXTRACT_ROOT"

[[ -f "$APPLIANCE_INSTALLER" ]] \
    || fail "NetFortress appliance installer was not extracted correctly"

ok "NetFortress appliance source extracted"

###############################################################################
# Run the native NetFortress installer
###############################################################################

log "INSTALLING NETFORTRESS FIREWALL APPLIANCE"

bash "$APPLIANCE_INSTALLER"

###############################################################################
# Wait for the appliance API
###############################################################################

log "VERIFYING APPLIANCE"

API_READY=0

for i in {1..45}; do

    if curl -fsS \
        --max-time 2 \
        http://127.0.0.1:8080/api/v1/health \
        >/dev/null 2>&1; then

        API_READY=1
        break
    fi

    sleep 2
done

if [[ "$API_READY" -ne 1 ]]; then
    systemctl status firewall-api --no-pager || true
    journalctl -u firewall-api -n 50 --no-pager || true
    fail "NetFortress appliance API did not become ready."
fi

ok "NetFortress appliance API is responding"

if systemctl is-active --quiet firewall-policy-refresh.timer; then
    ok "Enforcement reconciler is scheduled"
else
    warn "Enforcement reconciler timer is not active"
fi

###############################################################################
# Final report
###############################################################################

log "INSTALLATION COMPLETE"

HOST_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -m1 -E '^[0-9]+(\.[0-9]+){3}$' || true)"
HOST_IP="${HOST_IP:-Unknown}"

echo
echo "NetFortress Firewall Appliance:"
echo "  Web console:  http://$HOST_IP:8080"
echo "  API:          http://127.0.0.1:8080"
echo "  Source:       $EXTRACT_ROOT/firewall-appliance"
echo "  Installed at: /opt/firewall-appliance"
echo
echo "Licensing:"
echo "  The 60-day full-feature trial starts automatically on a fresh"
echo "  install. When it runs out, the appliance continues automatically"
echo "  on the free Home Lite licence (10 devices, one account)."
echo
echo "Next steps:"
echo "  1. Open the web console and create the administrator account."
echo "  2. Configure the network interfaces and DNS/DHCP settings."
echo "  3. Optional modules (IDS/IPS, HTTPS block page, GeoIP, ACME)"
echo "     install from the web console under Security modules."
echo
echo "All installation tests completed successfully."
echo