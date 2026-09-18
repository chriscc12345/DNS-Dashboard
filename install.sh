
#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Portal Server - Debian 13 Installer
#
# Installs:
#   - PostgreSQL
#   - NGINX
#   - PHP 8.4 FPM
#   - Python / FastAPI
#   - Technitium DNS
#
# Restores:
#   - Exact PostgreSQL database dump
#   - Portal source archive
#
# Configures:
#   - Portal FastAPI systemd service
#   - NGINX HTTPS
#   - Self-signed SSL certificate
#   - Technitium portal-api user
#   - Technitium API token
#
# No firewall configuration.
# No Fail2Ban.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

TECH_ROOT="/opt/technitium"
TECH_DNS="$TECH_ROOT/dns"
TECH_CONFIG="/etc/dns"

TECH_HOST="127.0.0.1"
TECH_PORT="5380"

DEFAULT_PORTAL_HOSTNAME="portal.example.com"

SSL_DIR="/etc/ssl/portal"
SSL_KEY="$SSL_DIR/server.key"
SSL_CERT="$SSL_DIR/server.crt"

API_SERVICE="portal-api.service"

UPDATE_STATE_DIR="/var/lib/portal"
UPDATE_STATE_FILE="$UPDATE_STATE_DIR/update-version"

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
    unset TECH_ADMIN_TOKEN
    unset TECH_API_PASSWORD
    unset TECH_API_TOKEN
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

mkdir -p "$PORTAL_ROOT"

# Preserve the existing portal-api Technitium token before replacing the
# Portal source. On a rerun this token can authenticate provisioning even
# when the Technitium admin password is no longer the default admin/admin.
EXISTING_TECH_API_TOKEN=""

if [[ -f "$PORTAL_API/config.py" ]]; then
    EXISTING_TECH_API_TOKEN="$(
        python3 - "$PORTAL_API/config.py" <<'PYTOKEN'
from pathlib import Path
import ast
import sys

tree = ast.parse(Path(sys.argv[1]).read_text())

for node in tree.body:
    if not isinstance(node, ast.Assign):
        continue

    for target in node.targets:
        if isinstance(target, ast.Name) and target.id == "TECHNITIUM_TOKEN":
            if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
                print(node.value.value)
                raise SystemExit(0)
PYTOKEN
    )"
fi

if [[ -n "$EXISTING_TECH_API_TOKEN" ]]; then
    ok "Existing Technitium Portal API token preserved for rerun"
fi

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

ok "Portal source installed"

###############################################################################
# Patch Portal Technitium authentication for current API
###############################################################################

log "UPDATING PORTAL TECHNITIUM API AUTHENTICATION"

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

# Parse the ORIGINAL Portal source and locate only requests.get()/requests.post()
# calls that actually reference TECHNITIUM_TOKEN. Using Python's AST prevents a
# regex from spanning unrelated functions or requests.
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

    # User login authenticates with the username/password entered in the Portal.
    # It must NEVER receive the portal-api service Bearer token.
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

# Patch each matching request independently, working backwards so offsets remain
# valid. This cannot cross into /api/user/login or another request.
for start, end in sorted(token_calls, reverse=True):
    block = text[start:end]
    original_block = block

    # Remove the legacy Technitium token from params.
    #
    # The Portal source uses:
    #     "token": TECHNITIUM_TOKEN,
    #
    # Authentication is now supplied with:
    #     Authorization: Bearer <portal-api token>
    #
    # Work only inside this individual AST-selected requests call.
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

    # If the token is still present, the source uses a form we have not
    # explicitly handled. Abort rather than silently damaging main.py.
    if "TECHNITIUM_TOKEN" in block:
        raise SystemExit(
            "Unsupported TECHNITIUM_TOKEN syntax found in a requests call; "
            "Portal main.py was not modified."
        )

    if "headers=TECHNITIUM_HEADERS" not in block:
        # Prefer inserting immediately before params/data/json/timeout.
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
            # Fall back to inserting before the request call's closing ')'.
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

# TECHNITIUM_TOKEN is imported from config.py via:
#     from config import *
#
# Define the reusable Bearer header immediately after that import.
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

# Safety check: /login must still call Technitium's user-login endpoint and must
# not contain the portal-api Bearer header.
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
        "Portal Technitium authentication could not be patched automatically."
    )

path.write_text(text)
PY

ok "Portal Technitium authentication patched"

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
# Technitium DNS
###############################################################################

log "INSTALLING TECHNITIUM DNS"

if systemctl cat dns.service >/dev/null 2>&1; then

    ok "Technitium dns.service already installed"

elif [[ -d "$TECH_DNS" && -f "$TECH_DNS/DnsServerApp.dll" ]]; then

    ok "Technitium installation already exists"

else

    curl -fsSL \
        https://download.technitium.com/dns/install.sh |
        bash

fi

###############################################################################
# Fix Technitium filesystem traversal permissions
###############################################################################

log "FIXING TECHNITIUM PERMISSIONS"

mkdir -p /opt
chmod 755 /opt

if [[ -d "$TECH_ROOT" ]]; then
    chmod 755 "$TECH_ROOT"
fi

if [[ -d "$TECH_DNS" ]]; then
    chmod 755 "$TECH_DNS"
fi

mkdir -p "$TECH_CONFIG"

ok "Technitium directory permissions configured"

###############################################################################
# Start Technitium
###############################################################################

log "STARTING TECHNITIUM DNS"

systemctl daemon-reload
systemctl enable dns.service
systemctl restart dns.service

TECH_READY=0

for i in {1..60}; do

    if curl -fsS \
        --max-time 2 \
        "http://${TECH_HOST}:${TECH_PORT}/api/status" \
        >/dev/null 2>&1; then

        TECH_READY=1
        break
    fi

    sleep 2
done

if [[ "$TECH_READY" -ne 1 ]]; then
    systemctl status dns.service --no-pager || true
    journalctl -u dns.service -n 50 --no-pager || true
    fail "Technitium API did not become ready."
fi

ok "Technitium API is responding"

###############################################################################
# Technitium API provisioning
###############################################################################

log "CONFIGURING TECHNITIUM PORTAL API USER"

TECH_API_USER="portal-api"

# Generate a random password only for creating the Technitium account.
TECH_API_PASSWORD="$(openssl rand -hex 32)"

# IMPORTANT:
# Do not print the password or token.
#
# Technitium documentation confirms:
#   /api/user/login
#   /api/admin/users/create
#   /api/admin/users/set
#   /api/user/createToken
#
# API authentication uses:
#   Authorization: Bearer <token>

TECH_ADMIN_TOKEN=""
TECH_RERUN_EXISTING=0

# On a rerun, prefer the existing portal-api Bearer token. The portal-api
# account is an Administrators member, so its token can perform provisioning
# without depending on the Technitium admin password.
if [[ -n "${EXISTING_TECH_API_TOKEN:-}" ]]; then

    EXISTING_TOKEN_TEST="$(
        curl -sS \
            --max-time 10 \
            -H "Authorization: Bearer $EXISTING_TECH_API_TOKEN" \
            "http://${TECH_HOST}:${TECH_PORT}/api/admin/users/list" \
            2>/dev/null || true
    )"

    if [[ "$(jq -r '.status // empty' <<<"$EXISTING_TOKEN_TEST")" == "ok" ]]; then
        TECH_ADMIN_TOKEN="$EXISTING_TECH_API_TOKEN"
        TECH_RERUN_EXISTING=1
        ok "Existing portal-api token accepted for Technitium provisioning"
    fi
fi

# Fresh Technitium installation: fall back to the default administrator
# credentials when no usable existing portal-api token is available.
if [[ -z "$TECH_ADMIN_TOKEN" ]]; then

    LOGIN_RESPONSE="$(
        curl -sS \
            --max-time 10 \
            --get \
            --data-urlencode "user=admin" \
            --data-urlencode "pass=admin" \
            --data-urlencode "includeInfo=true" \
            "http://${TECH_HOST}:${TECH_PORT}/api/user/login"
    )"

    if [[ "$(jq -r '.status // empty' <<<"$LOGIN_RESPONSE")" == "ok" ]]; then
        TECH_ADMIN_TOKEN="$(jq -r '.token // empty' <<<"$LOGIN_RESPONSE")"
    fi

    if [[ -z "$TECH_ADMIN_TOKEN" ]]; then
        fail "No valid Technitium administrative credential is available."
    fi

    ok "Technitium administrator login succeeded"
fi

###############################################################################
# Check/create portal-api user
###############################################################################

if [[ "$TECH_RERUN_EXISTING" -eq 1 ]]; then

    ###########################################################################
    # Rerun: keep existing portal-api user and token
    ###########################################################################

    log "REUSING EXISTING TECHNITIUM PORTAL API USER"

    USER_CHECK_RESPONSE="$(
        curl -fsS \
            --max-time 10 \
            -H "Authorization: Bearer $TECH_ADMIN_TOKEN" \
            --get \
            --data-urlencode "user=$TECH_API_USER" \
            --data-urlencode "includeGroups=true" \
            "http://${TECH_HOST}:${TECH_PORT}/api/admin/users/get"
    )"

    USER_STATUS="$(jq -r '.status // empty' <<<"$USER_CHECK_RESPONSE")"

    if [[ "$USER_STATUS" != "ok" ]]; then
        USER_ERROR="$(jq -r '.errorMessage // "Unknown Technitium error"' <<<"$USER_CHECK_RESPONSE")"
        fail "Existing $TECH_API_USER user could not be verified: $USER_ERROR"
    fi

    TECH_API_TOKEN="$EXISTING_TECH_API_TOKEN"

    ok "Existing Technitium user $TECH_API_USER retained"
    ok "Existing Technitium API token retained"

else

    ###########################################################################
    # Fresh provisioning: create portal-api user
    ###########################################################################

    USER_CHECK_RESPONSE="$(
        curl -sS \
            --max-time 10 \
            -H "Authorization: Bearer $TECH_ADMIN_TOKEN" \
            --get \
            --data-urlencode "user=$TECH_API_USER" \
            --data-urlencode "includeGroups=true" \
            "http://${TECH_HOST}:${TECH_PORT}/api/admin/users/get" \
            2>/dev/null || true
    )"

    USER_EXISTS="$(jq -r '.status // empty' <<<"$USER_CHECK_RESPONSE")"

    if [[ "$USER_EXISTS" == "ok" ]]; then

        log "RECREATING EXISTING TECHNITIUM PORTAL API USER"

        DELETE_USER_RESPONSE="$(
            curl -fsS \
                --max-time 10 \
                -H "Authorization: Bearer $TECH_ADMIN_TOKEN" \
                --get \
                --data-urlencode "user=$TECH_API_USER" \
                "http://${TECH_HOST}:${TECH_PORT}/api/admin/users/delete"
        )"

        DELETE_STATUS="$(jq -r '.status // empty' <<<"$DELETE_USER_RESPONSE")"

        if [[ "$DELETE_STATUS" != "ok" ]]; then
            DELETE_ERROR="$(jq -r '.errorMessage // "Unknown Technitium error"' <<<"$DELETE_USER_RESPONSE")"
            fail "Could not delete existing $TECH_API_USER user: $DELETE_ERROR"
        fi

        ok "Existing Technitium user $TECH_API_USER deleted"
    fi

    ###########################################################################
    # Create portal-api user
    ###########################################################################

    CREATE_USER_RESPONSE="$(
        curl -fsS \
            --max-time 10 \
            -H "Authorization: Bearer $TECH_ADMIN_TOKEN" \
            --get \
            --data-urlencode "displayName=Portal API" \
            --data-urlencode "user=$TECH_API_USER" \
            --data-urlencode "pass=$TECH_API_PASSWORD" \
            "http://${TECH_HOST}:${TECH_PORT}/api/admin/users/create"
    )"

    CREATE_STATUS="$(jq -r '.status // empty' <<<"$CREATE_USER_RESPONSE")"

    if [[ "$CREATE_STATUS" != "ok" ]]; then
        CREATE_ERROR="$(jq -r '.errorMessage // "Unknown Technitium error"' <<<"$CREATE_USER_RESPONSE")"
        fail "Technitium portal-api user creation failed: $CREATE_ERROR"
    fi

    ok "Technitium user $TECH_API_USER created"

    ###########################################################################
    # Put portal-api in Administrators
    ###########################################################################

    SET_USER_RESPONSE="$(
        curl -fsS \
            --max-time 10 \
            -H "Authorization: Bearer $TECH_ADMIN_TOKEN" \
            --get \
            --data-urlencode "user=$TECH_API_USER" \
            --data-urlencode "displayName=Portal API" \
            --data-urlencode "pass=$TECH_API_PASSWORD" \
            --data-urlencode "disabled=false" \
            --data-urlencode "memberOfGroups=Administrators" \
            "http://${TECH_HOST}:${TECH_PORT}/api/admin/users/set"
    )"

    SET_STATUS="$(jq -r '.status // empty' <<<"$SET_USER_RESPONSE")"

    if [[ "$SET_STATUS" != "ok" ]]; then
        SET_ERROR="$(jq -r '.errorMessage // "Unknown Technitium error"' <<<"$SET_USER_RESPONSE")"
        fail "Failed to add portal-api to Administrators: $SET_ERROR"
    fi

    ok "portal-api assigned to Administrators"

    ###########################################################################
    # Create non-expiring API token
    ###########################################################################

    log "CREATING TECHNITIUM API TOKEN"

    TOKEN_RESPONSE="$(
        curl -sS \
            --max-time 10 \
            --get \
            --data-urlencode "user=$TECH_API_USER" \
            --data-urlencode "pass=$TECH_API_PASSWORD" \
            --data-urlencode "tokenName=Portal API" \
            "http://${TECH_HOST}:${TECH_PORT}/api/user/createToken"
    )"

    TOKEN_STATUS="$(jq -r '.status // empty' <<<"$TOKEN_RESPONSE")"

    if [[ "$TOKEN_STATUS" != "ok" ]]; then
        TOKEN_ERROR="$(jq -r '.errorMessage // "Unknown Technitium error"' <<<"$TOKEN_RESPONSE")"
        fail "Technitium API token creation failed: $TOKEN_ERROR"
    fi

    TECH_API_TOKEN="$(
        jq -r '.token // .response.token // empty' <<<"$TOKEN_RESPONSE"
    )"

    if [[ -z "$TECH_API_TOKEN" ]]; then
        fail "Technitium returned status ok but no API token."
    fi

    ok "Technitium API token created"

fi

###############################################################################
# Validate portal-api token
###############################################################################

log "VERIFYING TECHNITIUM API TOKEN"

TOKEN_TEST="$(
    curl -fsS \
        --max-time 10 \
        -H "Authorization: Bearer $TECH_API_TOKEN" \
        "http://${TECH_HOST}:${TECH_PORT}/api/user/profile/get"
)"

TOKEN_TEST_USER="$(jq -r '.response.username // empty' <<<"$TOKEN_TEST")"

if [[ "$TOKEN_TEST_USER" != "$TECH_API_USER" ]]; then
    fail "Technitium API token belongs to unexpected user: ${TOKEN_TEST_USER:-unknown}"
fi

ok "Technitium API token validated"

###############################################################################
# Store token securely
###############################################################################

log "CONFIGURING PORTAL TECHNITIUM TOKEN"

CONFIG_FILE="$PORTAL_API/config.py"

if [[ ! -f "$CONFIG_FILE" ]]; then
    fail "Portal config.py not found: $CONFIG_FILE"
fi

chmod 600 "$CONFIG_FILE"

python3 - "$CONFIG_FILE" "$TECH_API_TOKEN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
token = sys.argv[2]

text = path.read_text()

pattern = r'(^TECHNITIUM_TOKEN\s*=\s*)["\'][^"\']*["\']'

replacement = rf'\1"{token}"'

text, count = re.subn(
    pattern,
    replacement,
    text,
    count=1,
    flags=re.MULTILINE
)

if count == 0:
    # Add the variable if the source does not currently define it.
    text = f'TECHNITIUM_TOKEN = "{token}"\n\n' + text

path.write_text(text)
PY

chmod 600 "$CONFIG_FILE"

ok "Technitium token inserted into Portal configuration"

###############################################################################
# Clear secrets from shell environment
###############################################################################

unset TECH_ADMIN_TOKEN
unset TECH_API_PASSWORD

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
# Portal -> Technitium test
###############################################################################

log "TESTING PORTAL -> TECHNITIUM"

PORTAL_TECH_TEST="$(
    curl -fsS \
        --max-time 10 \
        "http://127.0.0.1:8000/users"
)"

if grep -q '"status":"invalid-token"' <<<"$PORTAL_TECH_TEST"; then
    echo "Portal returned invalid-token from Technitium."
    exit 1
fi

if grep -q '"status": "invalid-token"' <<<"$PORTAL_TECH_TEST"; then
    echo "Portal returned invalid-token from Technitium."
    exit 1
fi

if grep -q '"status":"error"' <<<"$PORTAL_TECH_TEST"; then
    echo "Portal returned an error while communicating with Technitium."
    exit 1
fi

ok "Portal -> Technitium API connection works"

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
check_service dns.service "Technitium DNS"
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
# Technitium final test
###############################################################################

log "TECHNITIUM VERIFICATION"

if curl -fsS \
    --max-time 10 \
    "http://${TECH_HOST}:${TECH_PORT}/api/status" \
    >/dev/null; then

    ok "Technitium API responds"
else
    fail "Technitium API final test failed."
fi

###############################################################################
# Initialize Portal update state
###############################################################################

log "INITIALIZING PORTAL UPDATE STATE"

mkdir -p "$UPDATE_STATE_DIR"
chmod 755 "$UPDATE_STATE_DIR"

if [[ ! -f "$UPDATE_STATE_FILE" ]]; then
    printf '%s\n' "0" > "$UPDATE_STATE_FILE"
    chmod 644 "$UPDATE_STATE_FILE"
    ok "Portal update level initialized to 0"
else
    CURRENT_UPDATE_LEVEL="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"

    if [[ "$CURRENT_UPDATE_LEVEL" =~ ^[0-9]+$ ]]; then
        ok "Existing Portal update level retained: $CURRENT_UPDATE_LEVEL"
    else
        fail "Invalid Portal update state: $UPDATE_STATE_FILE"
    fi
fi

###############################################################################
# Check for Portal updates
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
        warn "Base Portal installation will remain active"
    fi
else
    FINAL_UPDATE_LEVEL="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"
    warn "Portal update checker not found: $UPDATE_CHECKER"
    warn "Installed update level remains $FINAL_UPDATE_LEVEL"
fi

###############################################################################
# Cleanup
###############################################################################

rm -f /tmp/portal-config-read
rm -rf /tmp/portal-source-read
rm -rf /tmp/portal-extract

unset TECH_API_TOKEN

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
echo "  Technitium: dns.service"
echo
echo "Technitium:"
echo "  Web Console: http://127.0.0.1:$TECH_PORT/"
echo "  API User:    portal-api"
echo "  Privileges:  Administrators"
echo "  API Token:   configured"
echo
echo "Security:"
echo "  Firewall:    NOT configured"
echo "  Fail2Ban:    NOT installed"
echo "  Apache:      removed/not installed"
echo
echo "All installation tests completed successfully."
echo
