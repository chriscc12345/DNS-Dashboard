#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Portal Deployment Launcher
#
# Chooses the deployment architecture before installing:
#
#   technitium - Management Portal + Technitium DNS
#                (the full stack installer: PostgreSQL, NGINX, PHP,
#                 FastAPI portal + Technitium DNS on this server)
#
#   firewall   - Management Portal + Firewall Appliance
#                (portal only; DNS/network services are provided by
#                 a separate Firewall Appliance over its API)
#
# Usage:
#   ./install.sh                          interactive menu
#   ./install.sh --backend technitium     unattended, Portal + Technitium
#   ./install.sh --backend firewall       unattended, Portal + Firewall
#
# The selected architecture is recorded in the portal database
# (portal_settings.dns_provider) after a successful installation,
# which is what the portal backend reads at runtime.
###############################################################################

LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TECHNITIUM_INSTALLER="$LAUNCHER_DIR/installers/install-technitium.sh"
FIREWALL_INSTALLER="$LAUNCHER_DIR/installers/install-firewall.sh"

BACKEND=""

usage() {
    echo "Usage: $0 [--backend technitium|firewall]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            BACKEND="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "This installer must be run as root" >&2; exit 1; }

if [[ -n "$BACKEND" && "$BACKEND" != "technitium" && "$BACKEND" != "firewall" ]]; then
    echo "[ERROR] Unknown backend: $BACKEND (expected technitium or firewall)" >&2
    exit 1
fi

###############################################################################
# Interactive menu
###############################################################################

if [[ -z "$BACKEND" ]]; then

    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "[INFO] No interactive terminal; defaulting to Technitium DNS backend"
        BACKEND="technitium"
    elif command -v whiptail >/dev/null 2>&1; then

        CHOICE="$(whiptail \
            --title "Portal Deployment" \
            --menu "\nSelect the deployment architecture:" \
            15 78 2 \
            "1" "Management Portal + Technitium DNS   (recommended)" \
            "2" "Management Portal + NetFortress Firewall Appliance" \
            3>&1 1>&2 2>&3)" || {
                echo "[INFO] Selection cancelled"
                exit 1
            }

        case "$CHOICE" in
            1) BACKEND="technitium" ;;
            2) BACKEND="firewall" ;;
            *) echo "[ERROR] Invalid selection" >&2; exit 1 ;;
        esac

    else

        echo
        echo "======================================================"
        echo " Portal Deployment - select the architecture:"
        echo "======================================================"
        echo "  1) Management Portal + Technitium DNS   (recommended)"
        echo "  2) Management Portal + NetFortress Firewall Appliance"
        echo
        read -r -p "Choice [1-2]: " CHOICE

        case "${CHOICE:-1}" in
            1) BACKEND="technitium" ;;
            2) BACKEND="firewall" ;;
            *) echo "[ERROR] Invalid selection" >&2; exit 1 ;;
        esac

    fi
fi

###############################################################################
# Dispatch
###############################################################################

echo
echo "======================================================================"
echo " Portal deployment: $BACKEND"
echo "======================================================================"

if [[ "$BACKEND" == "firewall" ]] && [[ ! -f "$FIREWALL_INSTALLER" ]]; then
    echo "[ERROR] Installer not found: $FIREWALL_INSTALLER" >&2
    exit 1
fi

if [[ "$BACKEND" == "technitium" ]] && [[ ! -f "$TECHNITIUM_INSTALLER" ]]; then
    echo "[ERROR] Installer not found: $TECHNITIUM_INSTALLER" >&2
    exit 1
fi

if [[ "$BACKEND" == "firewall" ]]; then
    bash "$FIREWALL_INSTALLER"
else
    bash "$TECHNITIUM_INSTALLER"
fi

###############################################################################
# Record the selected architecture
###############################################################################

if command -v psql >/dev/null 2>&1 \
    && sudo -u postgres psql -lqt -At -d postgres 2>/dev/null \
        | cut -d'|' -f1 | grep -qx 'dnsapproval'; then

    sudo -u postgres psql -d dnsapproval >/dev/null 2>&1 <<SQL || true
INSERT INTO portal_settings (setting_key, setting_value)
VALUES ('dns_provider', '$BACKEND')
ON CONFLICT (setting_key)
DO UPDATE SET setting_value = EXCLUDED.setting_value;
SQL

    echo "[ OK ] Deployment architecture recorded: $BACKEND"
else
    echo "[WARN] Could not record the deployment architecture in the database"
fi

echo
echo "INSTALLATION COMPLETE - deployment: $BACKEND"
