#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Portal Server - Debian 13 Installer (NetFortress Firewall Appliance)
#
# Deployment option 2: Management Portal + NetFortress Firewall
# Appliance. Nothing else.
#
# Installs on this server:
#   - PostgreSQL
#   - NGINX
#   - PHP 8.4 FPM
#   - Python / FastAPI portal
#
# No DNS server is installed on this server: DNS/network services
# are provided by the NetFortress Firewall Appliance over its API.
#
# The installer:
#   - Prompts for the appliance API URL and administrator credentials
#   - Verifies the appliance licence includes the required features
#   - Mints a scoped appliance API token (dns:read + dns:write)
#   - Configures the portal to drive the appliance through the
#     provider abstraction (dns_provider=firewall)
#
# No firewall configuration.
# No Fail2Ban.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB_DUMP="$SCRIPT_DIR/database/dnsapproval.dump"
PORTAL_ARCHIVE="$SCRIPT_DIR/portal/portal-source.tar.gz"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"
NGINX_CONFIG="$SCRIPT_DIR/nginx/default"
PORTAL_SERVICE="$SCRIPT_DIR/systemd/portal-api.service"

LOG_FILE="/var/log/portal-server-installer.log"

DB_NAME="dnsapproval"
DB_USER="dnsapp"

PORTAL_ROOT="/opt/portal"
PORTAL_API="$PORTAL_ROOT/api"
PORTAL_WEB="$PORTAL_ROOT/web"

DEFAULT_PORTAL_HOSTNAME="portal.example.com"

SSL_DIR="/etc/ssl/portal"
SSL_KEY="$SSL_DIR/server.key"
SSL_CERT="$SSL_DIR/server.crt"

API_SERVICE="portal-api.service"

UPDATE_STATE_DIR="/var/lib/portal"
UPDATE_STATE_FILE="$UPDATE_STATE_DIR/update-version"

# NetFortress Firewall Appliance integration (filled in by the
# integration phase at the end of the install)
FIREWALL_API_URL=""
FIREWALL_ADMIN_USER=""
FIREWALL_ADMIN_PASSWORD=""
FIREWALL_ADMIN_SESSION=""
FIREWALL_API_TOKEN=""

export DEBIAN_FRONTEND=noninteractive

###############################################################################
# Logging
###############################################################################

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

ok() {
    echo "[ OK ] $1"
}

warn() {
    echo "[WARN] $1"
}

error() {
    echo "[ERROR] $1"
}

fail() {
    error "$1"
    exit 1
}

cleanup() {
    unset DB_PASSWORD
    unset DB_PASSWORD_SQL
    unset FIREWALL_ADMIN_PASSWORD
    unset FIREWALL_ADMIN_SESSION
    unset FIREWALL_API_TOKEN
}

trap cleanup EXIT

###############################################################################
# Portal hostname
###############################################################################

read -r -p "Portal hostname [$DEFAULT_PORTAL_HOSTNAME]: " PORTAL_HOSTNAME
PORTAL_HOSTNAME="${PORTAL_HOSTNAME:-$DEFAULT_PORTAL_HOSTNAME}"

# Hostname only - no protocol, port, path, spaces, or shell metacharacters.
if [[ ! "$PORTAL_HOSTNAME" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
    fail "Invalid Portal hostname: $PORTAL_HOSTNAME"
fi

PORTAL_HOSTNAME="${PORTAL_HOSTNAME,,}"

###############################################################################
# Root check
###############################################################################

if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this installer as root."
fi

###############################################################################
# Debian check
###############################################################################

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

[[ -f "$DB_DUMP" ]] || fail "Database dump not found: $DB_DUMP"
[[ -f "$PORTAL_ARCHIVE" ]] || fail "Portal archive not found: $PORTAL_ARCHIVE"
[[ -f "$REQUIREMENTS" ]] || fail "requirements.txt not found: $REQUIREMENTS"
[[ -f "$NGINX_CONFIG" ]] || fail "NGINX config not found: $NGINX_CONFIG"
[[ -f "$PORTAL_SERVICE" ]] || fail "Portal systemd service not found: $PORTAL_SERVICE"

ok "Database dump found"
ok "Portal source archive found"
ok "Python requirements found"
ok "NGINX configuration found"
ok "Portal systemd service found"

###############################################################################
# Fix /opt traversal permissions
###############################################################################

log "FIXING /OPT DIRECTORY PERMISSIONS"

mkdir -p /opt
chmod 755 /opt

ok "/opt permissions set to 755"

###############################################################################
# Update package information
###############################################################################

log "APT UPDATE"

apt update
apt upgrade -y

###############################################################################
# Remove Apache if present
###############################################################################

log "REMOVING APACHE"

if dpkg-query -W -f='${Status}' apache2 2>/dev/null | grep -q "install ok installed"; then
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true

    apt purge -y \
        apache2 \
        apache2-bin \
        apache2-data \
        apache2-utils \
        libapache2-mod-php8.4 \
        libapache2-mod-php \
        2>/dev/null || true

    apt-get autoremove -y || true
fi

ok "Apache removed/not installed"

###############################################################################
# Install required packages
###############################################################################

log "INSTALLING REQUIRED PACKAGES"

apt install -y \
    ca-certificates \
    curl \
    git \
    jq \
    nginx \
    openssl \
    patch \
    postgresql \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    unzip \
    php8.4-cli \
    php8.4-curl \
    php8.4-fpm \
    php8.4-mbstring \
    php8.4-pgsql \
    php8.4-xml

ok "Required packages installed"

###############################################################################
# PostgreSQL
###############################################################################

log "CONFIGURING POSTGRESQL"

systemctl enable postgresql
systemctl start postgresql

for i in {1..30}; do
    if sudo -u postgres pg_isready >/dev/null 2>&1; then
        break
    fi

    if [[ "$i" -eq 30 ]]; then
        fail "PostgreSQL did not become ready."
    fi

    sleep 2
done

ok "PostgreSQL is ready"

###############################################################################
# Generate Portal DB password
###############################################################################

log "GENERATING PORTAL DATABASE CREDENTIALS"

DB_PASSWORD="$(openssl rand -hex 32)"

if [[ -z "${DB_PASSWORD:-}" ]]; then
    fail "Could not generate Portal database password."
fi

ok "Portal database credentials generated"

###############################################################################
# Create PostgreSQL role
###############################################################################

log "CONFIGURING DATABASE ROLE"

if ! sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" |
    grep -q 1; then

    sudo -u postgres createuser "$DB_USER"

    ok "Created PostgreSQL role $DB_USER"
else
    ok "PostgreSQL role $DB_USER already exists"
fi

DB_PASSWORD_SQL="${DB_PASSWORD//\'/\'\'}"

sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE "$DB_USER" WITH LOGIN PASSWORD '$DB_PASSWORD_SQL';
SQL

unset DB_PASSWORD_SQL

ok "PostgreSQL role password configured"

###############################################################################
# Restore exact database dump
###############################################################################

log "RESTORING DATABASE"

RESTORE_DUMP="/tmp/dnsapproval-restore.dump"

cp "$DB_DUMP" "$RESTORE_DUMP"
chown postgres:postgres "$RESTORE_DUMP"
chmod 600 "$RESTORE_DUMP"

sudo -u postgres pg_restore \
    --dbname=postgres \
    --create \
    --clean \
    --if-exists \
    --exit-on-error \
    "$RESTORE_DUMP"

rm -f "$RESTORE_DUMP"

ok "Exact PostgreSQL database restored"

###############################################################################
# Verify database
###############################################################################

if ! sudo -u postgres psql -d "$DB_NAME" -tAc \
    "SELECT 1" | grep -q 1; then
    fail "Database $DB_NAME could not be opened."
fi

if ! PGPASSWORD="$DB_PASSWORD" psql \
    -h 127.0.0.1 \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -tAc "SELECT 1" >/dev/null 2>&1; then

    fail "Portal PostgreSQL credentials failed."
fi

ok "Portal PostgreSQL credentials work"

###############################################################################
# Install Portal source
###############################################################################

log "INSTALLING PORTAL SOURCE"

# Determine whether this is a genuinely fresh Portal installation before
# creating or replacing any Portal runtime directories.
FRESH_PORTAL_INSTALL=0

if [[ ! -d "$PORTAL_API" && ! -d "$PORTAL_WEB" ]]; then
    FRESH_PORTAL_INSTALL=1
    ok "Fresh Portal installation detected"
else
    ok "Existing Portal installation detected"
fi

mkdir -p "$PORTAL_ROOT"

rm -rf "$PORTAL_API" "$PORTAL_WEB"

tar -xzf "$PORTAL_ARCHIVE" -C /opt

# Handle archives containing /opt/portal
if [[ -d /opt/opt/portal ]]; then
    if [[ -d /opt/opt/portal/api ]]; then
        rm -rf "$PORTAL_ROOT"
        mv /opt/opt/portal "$PORTAL_ROOT"
    fi

    rm -rf /opt/opt
fi

# Handle archives containing portal/api and portal/web
if [[ ! -d "$PORTAL_API" || ! -d "$PORTAL_WEB" ]]; then

    EXTRACT_DIR="/tmp/portal-extract"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"

    tar -xzf "$PORTAL_ARCHIVE" -C "$EXTRACT_DIR"

    FOUND_API="$(find "$EXTRACT_DIR" -type d -path '*/api' -print -quit)"
    FOUND_WEB="$(find "$EXTRACT_DIR" -type d -path '*/web' -print -quit)"

    if [[ -n "$FOUND_API" && -n "$FOUND_WEB" ]]; then

        mkdir -p "$PORTAL_ROOT"

        rm -rf "$PORTAL_API" "$PORTAL_WEB"

        cp -a "$FOUND_API" "$PORTAL_API"
        cp -a "$FOUND_WEB" "$PORTAL_WEB"
    fi

    rm -rf "$EXTRACT_DIR"
fi

[[ -d "$PORTAL_API" ]] || fail "Portal API directory was not installed."
[[ -d "$PORTAL_WEB" ]] || fail "Portal web directory was not installed."

###############################################################################
# Configure Portal database credentials
###############################################################################

CONFIG_FILE="$PORTAL_API/config.py"

[[ -f "$CONFIG_FILE" ]] || fail "Portal config.py was not installed."

python3 - "$CONFIG_FILE" "$DB_PASSWORD" <<'PYDBCONFIG'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
password = sys.argv[2]

text = path.read_text()

pattern = r'(^POSTGRES_PASSWORD\s*=\s*)["\'][^"\']*["\']'

text, count = re.subn(
    pattern,
    lambda m: m.group(1) + repr(password),
    text,
    count=1,
    flags=re.MULTILINE,
)

if count != 1:
    raise SystemExit("Could not update POSTGRES_PASSWORD in Portal config.py")

path.write_text(text)
PYDBCONFIG

ok "Portal database credentials configured"

###############################################################################
# Firewall Appliance configuration placeholders
#
# The provider layer (update 006) imports FIREWALL_API_URL and
# FIREWALL_API_TOKEN from this file, so the keys must exist before
# the updates run. The integration phase at the end of this install
# replaces them with the real appliance values.
###############################################################################

python3 - "$CONFIG_FILE" <<'PYFIREWALLPLACEHOLDER'
from pathlib import Path
import sys

path = Path(sys.argv[1])
content = path.read_text()

if "FIREWALL_API_URL" not in content:
    if content and not content.endswith("\n"):
        content += "\n"
    content += (
        "\n"
        "# NetFortress Firewall Appliance (deployment option 2)\n"
        "# Replaced with real values by the appliance integration phase\n"
        'FIREWALL_API_URL = "http://127.0.0.1:8080"\n'
        'FIREWALL_API_TOKEN = ""\n'
    )
    path.write_text(content)
    print("[ OK ] Firewall Appliance placeholder keys added to API config")
else:
    print("[ OK ] Firewall Appliance keys already present")
PYFIREWALLPLACEHOLDER

ok "Portal source installed"

###############################################################################
# Prepare the Portal source for the update chain
#
# The update chain (001-006) is built against the Portal source in
# the state this patch produces: Technitium requests use the
# TECHNITIUM_HEADERS bearer header and the header definition sits
# directly after the config import. The exact same preparation the
# Technitium installer performs; without it update 002 does not
# apply cleanly. The Technitium code paths are never used by this
# deployment - the provider layer (update 006) replaces them - but
# the source must still be prepared for the updates to run.
###############################################################################

log "PREPARING PORTAL SOURCE FOR UPDATES"

MAIN_PY="$PORTAL_API/main.py"

if [[ ! -f "$MAIN_PY" ]]; then
    fail "Portal main.py not found."
fi

cp "$MAIN_PY" "${MAIN_PY}.pre-technitium-patch"

python3 - "$MAIN_PY" <<'PY'
from pathlib import Path
import ast
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
original = text

try:
    tree = ast.parse(text)
except SyntaxError as exc:
    raise SystemExit(f"Portal main.py could not be parsed: {exc}")

lines = text.splitlines(keepends=True)
line_offsets = [0]
for line in lines:
    line_offsets.append(line_offsets[-1] + len(line))

def absolute_offset(lineno, col):
    return line_offsets[lineno - 1] + col

token_calls = []

for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue

    func = node.func
    if not (
        isinstance(func, ast.Attribute)
        and func.attr in ("get", "post")
        and isinstance(func.value, ast.Name)
        and func.value.id == "requests"
    ):
        continue

    segment = ast.get_source_segment(text, node) or ""

    if "/api/user/login" in segment:
        continue

    if "TECHNITIUM_TOKEN" not in segment:
        continue

    if not hasattr(node, "end_lineno") or node.end_lineno is None:
        raise SystemExit("Python AST did not provide request-call end positions.")

    start = absolute_offset(node.lineno, node.col_offset)
    end = absolute_offset(node.end_lineno, node.end_col_offset)

    token_calls.append((start, end))

if not token_calls:
    raise SystemExit(
        "No Technitium requests using TECHNITIUM_TOKEN were found in Portal main.py."
    )

for start, end in sorted(token_calls, reverse=True):
    block = text[start:end]
    original_block = block

    token_pattern = r'["\']token["\']\s*:\s*TECHNITIUM_TOKEN\s*,?'

    block, token_count = re.subn(
        token_pattern,
        '',
        block,
        count=1
    )

    if token_count != 1:
        raise SystemExit(
            "Could not remove TECHNITIUM_TOKEN from a Technitium request."
        )

    if "TECHNITIUM_TOKEN" in block:
        raise SystemExit(
            "Unsupported TECHNITIUM_TOKEN syntax found in a requests call; "
            "Portal main.py was not modified."
        )

    if "headers=TECHNITIUM_HEADERS" not in block:
        m = re.search(
            r'(?m)^([ \t]*)(params|data|json|timeout)[ \t]*=',
            block
        )

        if m:
            indent = m.group(1)
            pos = m.start()
            block = (
                block[:pos]
                + f"{indent}headers=TECHNITIUM_HEADERS,\n"
                + block[pos:]
            )
        else:
            closing = block.rfind(")")
            if closing == -1:
                raise SystemExit(
                    "Could not safely add Technitium Authorization header."
                )

            indent_match = re.search(r'\n([ \t]+)\S', block)
            indent = indent_match.group(1) if indent_match else "    "

            prefix = block[:closing]
            if not prefix.endswith("\n"):
                prefix += "\n"

            block = (
                prefix
                + f"{indent}headers=TECHNITIUM_HEADERS\n"
                + block[closing:]
            )

    if block == original_block:
        raise SystemExit(
            "A Technitium token request was found but could not be converted."
        )

    text = text[:start] + block + text[end:]

if "TECHNITIUM_HEADERS =" not in text:
    config_import = "from config import *"

    if config_import not in text:
        raise SystemExit(
            "Could not locate 'from config import *' in Portal main.py."
        )

    text = text.replace(
        config_import,
        config_import
        + "\n\n"
        + 'TECHNITIUM_HEADERS = {"Authorization": f"Bearer {TECHNITIUM_TOKEN}"}',
        1
    )

try:
    patched_tree = ast.parse(text)
except SyntaxError as exc:
    raise SystemExit(f"Patched Portal main.py is invalid Python: {exc}")

login_checked = False

for node in patched_tree.body:
    if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
    if node.name != "login":
        continue

    segment = ast.get_source_segment(text, node) or ""

    if "/api/user/login" in segment:
        login_checked = True
        if "TECHNITIUM_HEADERS" in segment:
            raise SystemExit(
                "SECURITY ERROR: /api/user/login was assigned the portal-api "
                "Bearer header."
            )

if not login_checked:
    raise SystemExit(
        "Could not verify the Portal /login -> Technitium /api/user/login path."
    )

if text == original:
    raise SystemExit(
        "Portal source preparation could not be patched automatically."
    )

path.write_text(text)
PY

ok "Portal source prepared for updates"

###############################################################################
# Create Python virtual environment
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
# Portal systemd service
###############################################################################

log "INSTALLING PORTAL SYSTEMD SERVICE"

cp "$PORTAL_SERVICE" "/etc/systemd/system/$API_SERVICE"

systemctl daemon-reload
systemctl enable "$API_SERVICE"

ok "Portal systemd service installed"

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

cp "$NGINX_CONFIG" /etc/nginx/sites-available/default

sed -i \
    "s/__PORTAL_HOSTNAME__/$PORTAL_HOSTNAME/g" \
    /etc/nginx/sites-available/default

ln -sfn \
    /etc/nginx/sites-available/default \
    /etc/nginx/sites-enabled/default

nginx -t

systemctl enable nginx
systemctl restart nginx

if ! systemctl is-active --quiet nginx; then
    fail "NGINX is not running."
fi

ok "NGINX is running"

###############################################################################
# Start Portal API
###############################################################################

log "STARTING PORTAL FASTAPI"

systemctl daemon-reload
systemctl restart "$API_SERVICE"

FASTAPI_READY=0

for i in {1..45}; do

    if curl -fsS \
        --max-time 2 \
        http://127.0.0.1:8000/openapi.json \
        >/dev/null 2>&1; then

        FASTAPI_READY=1
        break
    fi

    sleep 2
done

if [[ "$FASTAPI_READY" -ne 1 ]]; then
    systemctl status "$API_SERVICE" --no-pager || true
    journalctl -u "$API_SERVICE" -n 50 --no-pager || true
    fail "FastAPI did not become ready."
fi

ok "FastAPI is responding"

###############################################################################
# NGINX validation
###############################################################################

log "TESTING NGINX"

nginx -t

ok "NGINX configuration is valid"

###############################################################################
# HTTPS test
###############################################################################

log "TESTING HTTPS"

HTTPS_STATUS="$(
    curl -k -s -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1/"
)"

if [[ "$HTTPS_STATUS" != "200" && "$HTTPS_STATUS" != "301" && "$HTTPS_STATUS" != "302" ]]; then
    fail "HTTPS Portal test failed. HTTP status: $HTTPS_STATUS"
fi

ok "HTTPS Portal responds"

###############################################################################
# Final service checks
###############################################################################

log "FINAL SERVICE CHECKS"

check_service() {

    local unit="$1"
    local display="$2"

    if systemctl is-active --quiet "$unit"; then
        ok "$display is running"
    else
        error "$display is NOT running"
        systemctl status "$unit" --no-pager || true
        return 1
    fi
}

check_service postgresql "PostgreSQL"
check_service nginx "NGINX"
check_service php8.4-fpm "PHP-FPM"
check_service "$API_SERVICE" "Portal FastAPI"

###############################################################################
# Database verification
###############################################################################

log "DATABASE VERIFICATION"

TABLE_COUNT="$(
    sudo -u postgres psql \
        -d "$DB_NAME" \
        -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
)"

if [[ "${TABLE_COUNT:-0}" -lt 1 ]]; then
    fail "Database appears to contain no public tables."
fi

ok "Database contains $TABLE_COUNT public tables"

###############################################################################
# Portal verification
###############################################################################

log "PORTAL VERIFICATION"

if curl -fsS \
    --max-time 10 \
    http://127.0.0.1:8000/openapi.json \
    >/dev/null; then

    ok "FastAPI API responds directly"
else
    fail "FastAPI direct API test failed."
fi

if curl -k -fsS \
    --max-time 10 \
    https://127.0.0.1/openapi.json \
    >/dev/null; then

    ok "FastAPI responds through NGINX HTTPS"
else
    fail "FastAPI HTTPS proxy test failed."
fi

###############################################################################
# Initialize Portal update state
###############################################################################

log "INITIALIZING PORTAL UPDATE STATE"

mkdir -p "$UPDATE_STATE_DIR"
chmod 755 "$UPDATE_STATE_DIR"

INSTALL_TIMESTAMP_FILE="$UPDATE_STATE_DIR/installed-at"

if [[ "$FRESH_PORTAL_INSTALL" -eq 1 ]]; then
    if [[ ! -f "$INSTALL_TIMESTAMP_FILE" ]]; then
        date --iso-8601=seconds > "$INSTALL_TIMESTAMP_FILE"
        chmod 644 "$INSTALL_TIMESTAMP_FILE"
        ok "Portal installation timestamp recorded"
    else
        ok "Existing Portal installation timestamp retained"
    fi
else
    if [[ -f "$INSTALL_TIMESTAMP_FILE" ]]; then
        ok "Existing Portal installation timestamp retained"
    else
        ok "Legacy Portal installation - initial setup not required"
    fi
fi

if [[ ! -f "$UPDATE_STATE_FILE" ]]; then
    printf '%s\n' "0" > "$UPDATE_STATE_FILE"
    chmod 644 "$UPDATE_STATE_FILE"
    ok "Portal update level initialized to 0"
else
    # Every installer run re-extracts the portal source and restores the
    # reference database, so a previous update level no longer describes
    # what is installed. Retaining it would make earlier updates skip and
    # leave the fresh source without their changes; the update chain must
    # rebuild from level 0.
    CURRENT_UPDATE_LEVEL="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"
    printf '%s\n' "0" > "$UPDATE_STATE_FILE"
    chmod 644 "$UPDATE_STATE_FILE"
    ok "Portal update level reset to 0 (source and database were re-installed; was: ${CURRENT_UPDATE_LEVEL:-unknown})"
fi

###############################################################################
# Check for Portal updates
#
# This brings a fresh install to the current update level, which
# includes the network-services provider abstraction (update 006).
###############################################################################

log "CHECKING FOR PORTAL UPDATES"

UPDATE_CHECKER="$SCRIPT_DIR/updates/check-updates.sh"

if [[ -f "$UPDATE_CHECKER" ]]; then
    chmod 755 "$UPDATE_CHECKER"

    if "$UPDATE_CHECKER"; then
        FINAL_UPDATE_LEVEL="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"
        ok "Portal update check completed - level $FINAL_UPDATE_LEVEL"
    else
        FINAL_UPDATE_LEVEL="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"
        warn "Portal update check failed - installed level remains $FINAL_UPDATE_LEVEL"
    fi
else
    FINAL_UPDATE_LEVEL="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"
    warn "Update checker not found: $UPDATE_CHECKER"
    warn "Installed update level remains $FINAL_UPDATE_LEVEL"
fi

# The NetFortress integration requires the provider abstraction
# (update 006). Never continue into appliance integration with an
# under-updated portal - the deployment would be half-configured.
if [[ ! "$FINAL_UPDATE_LEVEL" =~ ^[0-9]+$ ]] || (( FINAL_UPDATE_LEVEL < 6 )); then
    fail "Portal updates did not complete (level ${FINAL_UPDATE_LEVEL:-unknown}, update 006 required for the NetFortress integration). Check the update output above and re-run this installer."
fi

ok "Portal is at update level $FINAL_UPDATE_LEVEL (provider abstraction present)"

###############################################################################
# NetFortress Firewall Appliance integration
###############################################################################

log "CONFIGURING NETFORTRESS FIREWALL APPLIANCE"

echo
echo "Enter the NetFortress Firewall Appliance details."
echo "The portal drives DNS blocking through the appliance API"
echo "(domain blocks, approvals and licence limits)."
echo

# The appliance address is usually assigned by DHCP - there is no
# safe default, so it must be entered explicitly.
read -r -p "Appliance API URL (http://<appliance-ip>:8080): " FIREWALL_API_URL

if [[ ! "$FIREWALL_API_URL" =~ ^https?://[A-Za-z0-9.:-]+$ ]]; then
    fail "Invalid appliance API URL: $FIREWALL_API_URL"
fi

FIREWALL_API_URL="${FIREWALL_API_URL%/}"

read -r -p "Appliance administrator username: " FIREWALL_ADMIN_USER
[[ -n "$FIREWALL_ADMIN_USER" ]] || fail "Administrator username is required."

read -r -s -p "Appliance administrator password: " FIREWALL_ADMIN_PASSWORD
echo
[[ -n "$FIREWALL_ADMIN_PASSWORD" ]] || fail "Administrator password is required."

# -- Appliance reachability ----------------------------------------------

if ! curl -fsS --max-time 10 \
    "$FIREWALL_API_URL/api/v1/health" >/dev/null 2>&1; then
    fail "The appliance API is not reachable at $FIREWALL_API_URL"
fi

ok "Appliance API is reachable"

# -- Administrator login --------------------------------------------------

LOGIN_RESPONSE="$(
    curl -sS --max-time 15 \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$FIREWALL_ADMIN_USER\",\"password\":\"$FIREWALL_ADMIN_PASSWORD\"}" \
        "$FIREWALL_API_URL/api/v1/auth/login" 2>/dev/null || true
)"

FIREWALL_ADMIN_SESSION="$(
    jq -r '.access_token // empty' <<<"$LOGIN_RESPONSE" 2>/dev/null || true
)"

[[ -n "$FIREWALL_ADMIN_SESSION" ]] \
    || fail "Appliance administrator login failed (check username and password)"

ok "Appliance administrator login succeeded"

SESSION_HEADER="Authorization: Bearer $FIREWALL_ADMIN_SESSION"

# -- Licence precheck ------------------------------------------------------
#
# The provider needs the DNS features that ship with every edition
# from Home Lite upward:
#   dns             - DNS management (status, transactions)
#   dns_filtering   - domain block entries
#
# Token creation is authenticated by the appliance administrator
# session and is not licence-feature gated, so the integration works
# starting from the free Home Lite edition. A lesser (unlicensed /
# expired) appliance aborts here with a clear message instead of
# failing later during portal use.

LICENSE_RESPONSE="$(
    curl -sS --max-time 15 \
        -H "$SESSION_HEADER" \
        "$FIREWALL_API_URL/api/v1/licensing/status" 2>/dev/null || true
)"

LICENSE_EDITION="$(
    jq -r '.edition_label // "unknown"' <<<"$LICENSE_RESPONSE" 2>/dev/null || true
)"

MISSING_FEATURES=""

for feature in dns dns_filtering; do
    if ! jq -e --arg f "$feature" \
        '(.features // []) | index($f) != null' \
        <<<"$LICENSE_RESPONSE" >/dev/null 2>&1; then
        MISSING_FEATURES="$MISSING_FEATURES $feature"
    fi
done

if [[ -n "$MISSING_FEATURES" ]]; then
    fail "The appliance licence (edition: $LICENSE_EDITION) does not include the required features:$MISSING_FEATURES. Upgrade the appliance licence or choose the Technitium deployment."
fi

ok "Appliance licence verified (edition: $LICENSE_EDITION)"

LICENSE_ACCOUNT_LIMIT="$(
    jq -r '.account_limit // 0' <<<"$LICENSE_RESPONSE" 2>/dev/null || true
)"

if [[ "$LICENSE_ACCOUNT_LIMIT" =~ ^[0-9]+$ ]] && (( LICENSE_ACCOUNT_LIMIT > 0 )); then
    warn "The $LICENSE_EDITION licence allows $LICENSE_ACCOUNT_LIMIT portal user account(s); portal user creation will respect this limit"
fi

# -- Mint the portal API token ----------------------------------------------

TOKEN_RESPONSE="$(
    curl -sS --max-time 15 \
        -H "$SESSION_HEADER" \
        -H "Content-Type: application/json" \
        -d '{"name":"portal-provider","scopes":["dns:read","dns:write"]}' \
        "$FIREWALL_API_URL/api/v1/auth/tokens" 2>/dev/null || true
)"

FIREWALL_API_TOKEN="$(
    jq -r '.token // empty' <<<"$TOKEN_RESPONSE" 2>/dev/null || true
)"

[[ -n "$FIREWALL_API_TOKEN" ]] \
    || fail "Could not create the appliance API token (check the appliance licence and administrator privileges)"

ok "Appliance API token created (scopes: dns:read, dns:write)"

TOKEN_HEADER="Authorization: Bearer $FIREWALL_API_TOKEN"

# -- Validate the token against the appliance ------------------------------

TOKEN_TEST_STATUS="$(
    curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
        -H "$TOKEN_HEADER" \
        "$FIREWALL_API_URL/api/v1/dns/status" 2>/dev/null || true
)"

[[ "$TOKEN_TEST_STATUS" == "200" ]] \
    || fail "The appliance API token did not validate (HTTP $TOKEN_TEST_STATUS)"

ok "Appliance API token validated"

# -- Configure the portal ---------------------------------------------------

python3 - "$CONFIG_FILE" "$FIREWALL_API_URL" "$FIREWALL_API_TOKEN" <<'PYFIREWALLCONFIG'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
api_url = sys.argv[2]
api_token = sys.argv[3]

text = path.read_text()

for key, value in (
    ("FIREWALL_API_URL", api_url),
    ("FIREWALL_API_TOKEN", api_token),
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
        raise SystemExit("Could not set %s in Portal config.py" % key)

path.write_text(text)
PYFIREWALLCONFIG

ok "Appliance URL and token inserted into Portal configuration"

unset FIREWALL_ADMIN_PASSWORD
unset FIREWALL_ADMIN_SESSION

###############################################################################
# Restart the portal with the appliance configuration
###############################################################################

log "STARTING PORTAL WITH APPLIANCE BACKEND"

systemctl restart "$API_SERVICE"

FASTAPI_READY=0

for i in {1..45}; do

    if curl -fsS \
        --max-time 2 \
        http://127.0.0.1:8000/openapi.json \
        >/dev/null 2>&1; then

        FASTAPI_READY=1
        break
    fi

    sleep 2
done

if [[ "$FASTAPI_READY" -ne 1 ]]; then
    systemctl status "$API_SERVICE" --no-pager || true
    journalctl -u "$API_SERVICE" -n 50 --no-pager || true
    fail "FastAPI did not become ready with the appliance backend."
fi

ok "Portal FastAPI is running with the appliance backend"

###############################################################################
# Portal -> Appliance provider test
###############################################################################

log "TESTING PORTAL -> APPLIANCE"

PROVIDER_TEST="$(
    "$PORTAL_API/venv/bin/python" - <<'PYPROVIDER'
import sys

sys.path.insert(0, "/opt/portal/api")

from providers import active_provider_name, get_provider

name = active_provider_name()
provider = get_provider()

if name != "firewall" or provider.name != "firewall":
    print("ERROR: active provider is not the Firewall Appliance provider")
    raise SystemExit(1)

health = provider.health()

if health.get("status") != "ok":
    print("ERROR: appliance health check failed: %s" % health)
    raise SystemExit(1)

print("provider=%s dns_service=%s blocked_domains=%s" % (
    provider.name,
    health.get("dns_service"),
    health.get("blocked_domains"),
))
PYPROVIDER
)"

echo "$PROVIDER_TEST"

if grep -q "^provider=firewall " <<<"$PROVIDER_TEST"; then
    ok "Portal -> Firewall Appliance provider connection works"
else
    fail "Portal -> Firewall Appliance provider test failed"
fi

###############################################################################
# Record the deployment architecture
#
# Recorded only now that the integration is verified working. The
# launcher also records this after the installer exits.
###############################################################################

if sudo -u postgres psql -d "$DB_NAME" >/dev/null 2>&1 <<SQL
INSERT INTO portal_settings (setting_key, setting_value)
VALUES ('dns_provider', 'firewall')
ON CONFLICT (setting_key)
DO UPDATE SET setting_value = EXCLUDED.setting_value;
SQL
then
    ok "Deployment architecture recorded: firewall"
else
    warn "Could not record the deployment architecture in the database"
fi

###############################################################################
# Initial administrator setup note
###############################################################################

if [[ "$FRESH_PORTAL_INSTALL" -eq 1 ]]; then
    if [[ "$FINAL_UPDATE_LEVEL" =~ ^[0-9]+$ ]] \
       && (( FINAL_UPDATE_LEVEL >= 2 )) \
       && [[ -f "$PORTAL_WEB/setup.php" ]]; then

        ok "Initial administrator setup is ready - open https://$PORTAL_HOSTNAME/setup.php on first visit"
    else
        warn "Initial administrator setup page is not available on this installation"
    fi
fi

###############################################################################
# Cleanup
###############################################################################

rm -f /tmp/portal-config-read
rm -rf /tmp/portal-source-read
rm -rf /tmp/portal-extract

unset FIREWALL_API_TOKEN

###############################################################################
# Final report
###############################################################################

log "INSTALLATION COMPLETE"

HOST_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -m1 -E '^[0-9]+(\.[0-9]+){3}$' || true)"
HOST_IP="${HOST_IP:-Unknown}"

echo
echo "Portal:"
echo "  HTTPS: https://$PORTAL_HOSTNAME"
echo "  Host IP: $HOST_IP"
echo "  FastAPI: http://127.0.0.1:8000"
echo
echo "Services:"
echo "  PostgreSQL: postgresql"
echo "  NGINX:      nginx"
echo "  PHP-FPM:    php8.4-fpm"
echo "  Portal API: $API_SERVICE"
echo
echo "NetFortress Firewall Appliance:"
echo "  API URL:    $FIREWALL_API_URL"
echo "  Edition:    $LICENSE_EDITION"
echo "  API Token:  portal-provider (scopes: dns:read, dns:write)"
echo "  Provider:   firewall (recorded in portal settings)"
echo
echo "Security:"
echo "  Firewall:    NOT configured"
echo "  Fail2Ban:    NOT installed"
echo "  Apache:      removed/not installed"
echo
echo "All installation tests completed successfully."
echo