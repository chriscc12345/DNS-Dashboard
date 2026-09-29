#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# NetFortress Portal Installer
#
# Installs the Management Portal only: PostgreSQL, NGINX, PHP-FPM and
# the Portal FastAPI service. The portal ships with no network services
# backend; the administrator selects and provisions one (Technitium DNS
# or the NetFortress Firewall Appliance) afterwards from
# Settings -> System Status.
#
# Usage:
#   ./install.sh                          interactive
#   ./install.sh --hostname portal.example.com
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB_NAME="dnsapproval"
DB_USER="dnsapp"
MONITORING_DB_NAME="monitoring_db"
MONITORING_DB_USER="monitoring_user"

PORTAL_ROOT="/opt/portal"
PORTAL_API="$PORTAL_ROOT/api"
PORTAL_WEB="$PORTAL_ROOT/web"
PORTAL_SCRIPTS="$PORTAL_ROOT/scripts"

DB_DUMP="$SCRIPT_DIR/database/dnsapproval.sql"
MONITORING_SCHEMA="$SCRIPT_DIR/database/monitoring.sql"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"
PORTAL_ARCHIVE="$SCRIPT_DIR/portal/portal-source.tar.gz"
NGINX_CONFIG="$SCRIPT_DIR/nginx/portal"
PORTAL_SERVICE="$SCRIPT_DIR/systemd/portal-api.service"
HEARTBEAT_SERVICE="$SCRIPT_DIR/systemd/portal-heartbeat.service"
HEARTBEAT_TIMER="$SCRIPT_DIR/systemd/portal-heartbeat.timer"

API_SERVICE="portal-api.service"
SSL_DIR="/etc/ssl/portal"
SSL_KEY="$SSL_DIR/server.key"
SSL_CERT="$SSL_DIR/server.crt"

export DEBIAN_FRONTEND=noninteractive

###############################################################################
# Logging
###############################################################################

LOG_FILE="/var/log/portal-server-installer.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

###############################################################################
# Helpers
###############################################################################

log() {
    echo
    echo "======================================================================"
    echo "$1"
    echo "======================================================================"
}

ok() { echo "[ OK ] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; }

fail() {
    error "$1"
    exit 1
}

ask_input() {
    local title="$1" prompt="$2" default="${3:-}" answer=""

    if [[ -r /dev/tty && -w /dev/tty ]] && command -v whiptail >/dev/null 2>&1; then
        answer="$(whiptail --title "$title" --inputbox "$prompt" 12 70 "$default" 3>&1 1>&2 2>&3 || true)"
    else
        read -r -p "$prompt [$default]: " answer || true
    fi

    echo "${answer:-$default}"
}

###############################################################################
# Arguments
###############################################################################

DEFAULT_PORTAL_HOSTNAME="portal.example.com"
PORTAL_HOSTNAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            PORTAL_HOSTNAME="$2"
            shift 2
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

if [[ -z "$PORTAL_HOSTNAME" ]]; then
    log "PORTAL DEPLOYMENT"

    PORTAL_HOSTNAME="$(ask_input "Portal Deployment" "Portal hostname (the name users type in the browser):" "$DEFAULT_PORTAL_HOSTNAME")"
fi

if [[ ! "$PORTAL_HOSTNAME" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
    fail "Invalid Portal hostname: $PORTAL_HOSTNAME"
fi

PORTAL_HOSTNAME="${PORTAL_HOSTNAME,,}"

log " Portal hostname: $PORTAL_HOSTNAME "

###############################################################################
# System check
###############################################################################

log "SYSTEM CHECK"

if [[ -f /etc/debian_version ]]; then
    ok "Debian $(cat /etc/debian_version | cut -d. -f1)"
else
    fail "This installer targets Debian."
fi

if [[ $EUID -ne 0 ]]; then
    fail "This installer must be run as root."
fi

ok "Running as root"

###############################################################################
# Installer package check
###############################################################################

log "INSTALLER PACKAGE CHECK"

for f in "$DB_DUMP" "$MONITORING_SCHEMA" "$REQUIREMENTS" "$PORTAL_ARCHIVE" "$NGINX_CONFIG" "$PORTAL_SERVICE" "$HEARTBEAT_SERVICE" "$HEARTBEAT_TIMER"; do
    [[ -f "$f" ]] || fail "Required file not found: $f"
done

ok "Database baseline found"
ok "Monitoring schema found"
ok "Portal source archive found"
ok "Python requirements found"
ok "NGINX configuration found"
ok "Portal systemd services found"

###############################################################################
# Fixing /opt directory permissions
###############################################################################

log "FIXING /OPT DIRECTORY PERMISSIONS"

mkdir -p /opt
chmod 755 /opt

ok "/opt permissions set to 755"

###############################################################################
# APT update
###############################################################################

log "APT UPDATE"

apt-get update -qq || fail "apt update failed"

apt-get -yq full-upgrade || warn "System upgrade had warnings - continuing"

###############################################################################
# Removing Apache
###############################################################################

log "REMOVING APACHE"

if dpkg -l apache2 >/dev/null 2>&1; then
    apt-get -yq purge apache2 || true
    apt-get -yq autoremove || true
    ok "Apache removed"
else
    ok "Apache not installed"
fi

###############################################################################
# Installing required packages
###############################################################################

log "INSTALLING REQUIRED PACKAGES"

apt-get -yq install \
    ca-certificates curl git jq openssl patch python3 sudo unzip \
    nginx php8.4-cli php8.4-curl php8.4-fpm php8.4-mbstring \
    php8.4-pgsql php8.4-xml postgresql postgresql-client \
    python3-pip python3-venv \
    || fail "Required package installation failed"

ok "Required packages installed"

###############################################################################
# PostgreSQL
###############################################################################

log "CONFIGURING POSTGRESQL"

systemctl enable postgresql
systemctl start postgresql

for i in {1..15}; do
    if sudo -u postgres pg_isready -q; then
        ok "PostgreSQL is ready"
        break
    fi
    sleep 2
done

sudo -u postgres pg_isready -q || fail "PostgreSQL did not become ready"

###############################################################################
# Generating credentials
###############################################################################

log "GENERATING PORTAL DATABASE CREDENTIALS"

DB_PASSWORD="$(openssl rand -hex 32)"

if [[ -z "${DB_PASSWORD:-}" ]]; then
    fail "Could not generate Portal database password."
fi

ok "Portal database credentials generated"

log "GENERATING MONITORING DATABASE CREDENTIALS"

MONITORING_DB_PASSWORD="$(openssl rand -hex 32)"

if [[ -z "${MONITORING_DB_PASSWORD:-}" ]]; then
    fail "Could not generate monitoring database password."
fi

ok "Monitoring database credentials generated"

###############################################################################
# Database roles
###############################################################################

log "CONFIGURING DATABASE ROLES"

for ROLE in "$DB_USER" "$MONITORING_DB_USER"; do
    if ! sudo -u postgres psql -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='${ROLE}'" | grep -q 1; then
        sudo -u postgres createuser "$ROLE"
        ok "Created PostgreSQL role $ROLE"
    else
        ok "PostgreSQL role $ROLE already exists"
    fi
done

DB_PASSWORD_SQL="${DB_PASSWORD//\'/\'\'}"
MONITORING_DB_PASSWORD_SQL="${MONITORING_DB_PASSWORD//\'/\'\'}"

sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE "$DB_USER" WITH LOGIN PASSWORD '$DB_PASSWORD_SQL';
ALTER ROLE "$MONITORING_DB_USER" WITH LOGIN PASSWORD '$MONITORING_DB_PASSWORD_SQL';
SQL

unset DB_PASSWORD_SQL
unset MONITORING_DB_PASSWORD_SQL

ok "PostgreSQL role passwords configured"

###############################################################################
# Restore database baselines
###############################################################################

log "RESTORING DATABASE"

# The baseline is plain SQL and restores into any database name:
# the installer creates dnsapproval explicitly (a custom-format dump
# would restore into whatever name it was created from).

sudo -u postgres psql -qc "DROP DATABASE IF EXISTS $DB_NAME;"
# Transitional cleanup: an earlier baseline restore created a stray
# scratch database with this name; remove it if present.
sudo -u postgres psql -qc "DROP DATABASE IF EXISTS dnsapproval_v2;" 2>/dev/null || true
sudo -u postgres createdb "$DB_NAME"

sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d "$DB_NAME" -f "$DB_DUMP"

ok "Portal database restored"

# Monitoring database: owner is the monitoring role; schema is
# installed from the baseline (the old installers never created
# this database, which silently broke the heartbeat).

sudo -u postgres psql -qc "DROP DATABASE IF EXISTS $MONITORING_DB_NAME;"
sudo -u postgres createdb -O "$MONITORING_DB_USER" "$MONITORING_DB_NAME"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$MONITORING_DB_NAME" -f "$MONITORING_SCHEMA"

ok "Monitoring database created"

###############################################################################
# Database permissions and clean state
###############################################################################

log "CONFIGURING DATABASE PERMISSIONS"

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" <<'SQL'
GRANT ALL ON ALL TABLES IN SCHEMA public TO dnsapp;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO dnsapp;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO dnsapp;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO dnsapp;
SQL

ok "Portal database grants configured"

log "ENSURING CLEAN BASELINE STATE"

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" <<'SQL'
TRUNCATE requests;
DELETE FROM portal_auth;
DELETE FROM user_profiles;
DELETE FROM user_custom_field_values;
DELETE FROM portal_settings WHERE setting_key IN ('dns_provider', 'backend_provision');
SQL

ok "Baseline state verified"

if ! PGPASSWORD="$DB_PASSWORD" psql \
    -h 127.0.0.1 \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -tAc "SELECT 1" >/dev/null 2>&1; then

    fail "Portal PostgreSQL credentials failed."
fi

ok "Portal PostgreSQL credentials work"

if ! PGPASSWORD="$MONITORING_DB_PASSWORD" psql \
    -h 127.0.0.1 \
    -U "$MONITORING_DB_USER" \
    -d "$MONITORING_DB_NAME" \
    -tAc "SELECT 1" >/dev/null 2>&1; then

    fail "Monitoring PostgreSQL credentials failed."
fi

ok "Monitoring PostgreSQL credentials work"

###############################################################################
# Install Portal source
###############################################################################

log "INSTALLING PORTAL SOURCE"

rm -rf "$PORTAL_API" "$PORTAL_WEB" "$PORTAL_SCRIPTS"

tar -xzf "$PORTAL_ARCHIVE" -C /opt

if [[ -d /opt/opt/portal ]]; then
    rm -rf "$PORTAL_ROOT"
    mv /opt/opt/portal "$PORTAL_ROOT"
    rm -rf /opt/opt
fi

[[ -d "$PORTAL_API" && -d "$PORTAL_WEB" ]] \
    || fail "Portal source was not installed correctly"

[[ -f "$PORTAL_API/main.py" ]] || fail "Portal API source missing"
[[ -f "$PORTAL_API/config.py" ]] || fail "Portal config.py missing"
[[ -f "$PORTAL_API/providers/unconfigured.py" ]] || fail "Portal providers missing"
[[ -d "$PORTAL_API/backends" || -d "$PORTAL_ROOT/backends" ]] || fail "Backend provisioning scripts missing"

ok "Portal source installed"

###############################################################################
# Configure Portal credentials
###############################################################################

log "CONFIGURING PORTAL CREDENTIALS"

CONFIG_FILE="$PORTAL_API/config.py"

[[ -f "$CONFIG_FILE" ]] || fail "Portal config.py not found."

chmod 600 "$CONFIG_FILE"

python3 - "$CONFIG_FILE" "$DB_PASSWORD" "$MONITORING_DB_PASSWORD" <<'PYDBCONFIG'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
db_password = sys.argv[2]
monitoring_password = sys.argv[3]

text = path.read_text()

for key, value in (
    ("POSTGRES_PASSWORD", db_password),
    ("MONITORING_POSTGRES_PASSWORD", monitoring_password),
):
    pattern = r'(^%s\s*=\s*)["\'][^"\']*["\']' % key

    text, count = re.subn(
        pattern,
        lambda m, value=value: m.group(1) + repr(value),
        text,
        count=1,
        flags=re.MULTILINE,
    )

    if count != 1:
        raise SystemExit("Could not update %s in Portal config.py" % key)

path.write_text(text)
PYDBCONFIG

chmod 600 "$CONFIG_FILE"

ok "Portal credentials configured"

###############################################################################
# Python virtual environment
###############################################################################

log "CREATING PYTHON VIRTUAL ENVIRONMENT"

python3 -m venv "$PORTAL_API/venv"

"$PORTAL_API/venv/bin/pip" install --upgrade pip

"$PORTAL_API/venv/bin/pip" install \
    -r "$REQUIREMENTS"

ok "Python dependencies installed"

###############################################################################
# Portal permissions
###############################################################################

log "SETTING PORTAL PERMISSIONS"

chown -R root:root "$PORTAL_ROOT"
chmod 755 "$PORTAL_ROOT"
chmod 755 "$PORTAL_API"
chmod 755 "$PORTAL_WEB"

find "$PORTAL_WEB" -type d -exec chmod 755 {} \;
find "$PORTAL_WEB" -type f -exec chmod 644 {} \;

ok "Portal permissions configured"

###############################################################################
# Portal systemd services
###############################################################################

log "INSTALLING PORTAL SYSTEMD SERVICES"

cp "$PORTAL_SERVICE" "/etc/systemd/system/$API_SERVICE"
cp "$HEARTBEAT_SERVICE" /etc/systemd/system/portal-heartbeat.service
cp "$HEARTBEAT_TIMER" /etc/systemd/system/portal-heartbeat.timer

systemctl daemon-reload
systemctl enable "$API_SERVICE" portal-heartbeat.timer

ok "Portal systemd services installed"

###############################################################################
# PHP-FPM
###############################################################################

log "CONFIGURING PHP-FPM"

systemctl enable php8.4-fpm
systemctl restart php8.4-fpm

if ! systemctl is-active --quiet php8.4-fpm; then
    fail "PHP-FPM is not running."
fi

ok "PHP-FPM is running"

###############################################################################
# SSL certificate
###############################################################################

log "CONFIGURING SSL"

mkdir -p "$SSL_DIR"

if [[ ! -f "$SSL_KEY" || ! -f "$SSL_CERT" ]]; then

    openssl req \
        -x509 \
        -nodes \
        -newkey rsa:2048 \
        -keyout "$SSL_KEY" \
        -out "$SSL_CERT" \
        -days 365 \
        -subj "/CN=$PORTAL_HOSTNAME" \
        -addext "subjectAltName=DNS:$PORTAL_HOSTNAME"

    chmod 600 "$SSL_KEY"
    chmod 644 "$SSL_CERT"

    ok "Self-signed SSL certificate generated"
else
    ok "Existing SSL certificate retained"
fi

###############################################################################
# NGINX
###############################################################################

log "CONFIGURING NGINX"

mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

# The vhost is named 'portal': if the NetFortress appliance is
# provisioned later on this server, its reconciler removes any
# vhost named 'default' - this name is reconciler-safe.
cp "$NGINX_CONFIG" /etc/nginx/sites-available/portal

rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/portal

sed -i \
    "s/__PORTAL_HOSTNAME__/$PORTAL_HOSTNAME/g" \
    /etc/nginx/sites-available/portal

ln -sfn \
    /etc/nginx/sites-available/portal \
    /etc/nginx/sites-enabled/portal

nginx -t

systemctl enable nginx
systemctl restart nginx

if ! systemctl is-active --quiet nginx; then
    fail "NGINX is not running."
fi

ok "NGINX is running"

###############################################################################
# Start Portal
###############################################################################

log "STARTING PORTAL"

systemctl restart "$API_SERVICE"
systemctl start portal-heartbeat.timer

PORTAL_READY=0

for i in {1..45}; do
    if curl -fsS --max-time 2 \
        http://127.0.0.1:8000/openapi.json \
        >/dev/null 2>&1; then
        PORTAL_READY=1
        break
    fi
    sleep 2
done

if [[ "$PORTAL_READY" -ne 1 ]]; then
    systemctl status "$API_SERVICE" --no-pager || true
    journalctl -u "$API_SERVICE" -n 50 --no-pager || true
    fail "Portal API did not become ready."
fi

ok "Portal API is running"

###############################################################################
# Final checks
###############################################################################

log "FINAL SERVICE CHECKS"

for svc in postgresql nginx php8.4-fpm portal-api; do
    if systemctl is-active --quiet "$svc"; then
        ok "$svc is running"
    else
        fail "$svc is not running"
    fi
done

if systemctl is-active --quiet portal-heartbeat.timer; then
    ok "portal-heartbeat.timer is running"
else
    fail "portal-heartbeat.timer is not running"
fi

log "PORTAL VERIFICATION"

HOST_IP="$(hostname -I | awk '{print $1}')"

if curl -fsS --max-time 10 \
    http://127.0.0.1:8000/api/backends/status \
    >/dev/null 2>&1; then
    ok "Portal API responds"
else
    fail "Portal API did not respond"
fi

if curl -fskS --max-time 10 \
    --resolve "$PORTAL_HOSTNAME:443:127.0.0.1" \
    "https://$PORTAL_HOSTNAME/login.php" \
    >/dev/null 2>&1; then
    ok "Portal HTTPS responds"
else
    fail "Portal HTTPS did not respond"
fi

if curl -fskS --max-time 10 \
    --resolve "$PORTAL_HOSTNAME:443:127.0.0.1" \
    -o /dev/null -w '%{http_code}' \
    "https://$PORTAL_HOSTNAME/setup.php" \
    | grep -qE '^(200|302)$'; then
    ok "Initial setup page reachable"
else
    warn "Initial setup page did not respond"
fi

# Installation timestamp + setup requirement marker
mkdir -p /var/lib/portal
date -Iseconds > /var/lib/portal/installed-at
rm -f /var/lib/portal/initial-setup-complete
rm -f /var/lib/portal/update-version
rm -f /var/lib/portal/backend-provision.result

printf '1.0\n' > /var/lib/portal/portal-version
chmod 644 /var/lib/portal/portal-version

###############################################################################
# Summary
###############################################################################

log "INSTALLATION COMPLETE"

echo
echo "Portal:"
echo "  URL:      https://$PORTAL_HOSTNAME/login.php"
echo "  Host IP:  $HOST_IP"
echo "  Version:  1.0 (clean portal baseline)"
echo
echo "Next step:"
echo "  1. Open https://$PORTAL_HOSTNAME and complete the initial setup."
echo "  2. Sign in, then open Settings -> System Status and select the"
echo "     network services backend (Technitium DNS Server or the"
echo "     NetFortress Firewall Appliance). The portal provisions the"
echo "     selected backend in the background and adapts automatically."
echo
echo "Services:"
echo "  PostgreSQL:          postgresql"
echo "  NGINX:               nginx"
echo "  PHP-FPM:             php8.4-fpm"
echo "  Portal API:          portal-api.service"
echo "  Portal heartbeat:    portal-heartbeat.timer"
echo
echo "Security:"
echo "  Firewall:            NOT configured"
echo "  Fail2Ban:            NOT installed"
echo "  Apache:              removed/not installed"
echo
echo "All installation tests completed successfully."
