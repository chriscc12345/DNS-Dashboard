#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Portal Update 006
#
# Network services provider abstraction + NetFortress Firewall
# Appliance support.
#
# Brings a portal at update level 5 to level 6:
#
#   - Installs the providers package: the portal talks to its
#     DNS/network engine through one provider interface.
#   - Technitium provider: identical behaviour to before.
#   - NetFortress Firewall Appliance provider: drives the
#     appliance REST API (block/unblock with immediate guarded
#     activation, health, licence account limits).
#   - All block/unblock workflows in main.py route through the
#     active provider (portal_settings.dns_provider, default
#     technitium).
#   - When the appliance backend is active, the appliance
#     licence account limit applies to portal user creation.
#
# The api/config.py file is preserved; Firewall Appliance keys
# are appended if missing (placeholder values - deployment
# option 2 installs replace them with real appliance values).
###############################################################################

UPDATE_NAME="Update 006 - Network Services Provider Abstraction and Firewall Appliance Support"

DB_NAME="dnsapproval"
API_DIR="/opt/portal/api"
WEB_DIR="/opt/portal/web"
PORTAL_DIR="/opt/portal"
CONFIG_FILE="$API_DIR/config.py"
VERSION_FILE="/var/lib/portal/update-version"
BACKUP_ROOT="/var/backups/portal"
STAGE_DIR=""
BACKUP_DIR=""
CODE_BACKUP_DONE=0
DB_BACKUP_DONE=0

log() { printf '\n======================================================================\n%s\n======================================================================\n' "$1"; }
ok() { echo "[ OK ] $1"; }
warn() { echo "[WARN] $1"; }
fail() { echo "[ERROR] $1" >&2; return 1; }

on_error() {
    local rc=$?
    trap - ERR EXIT
    if [[ $rc -ne 0 ]]; then
        echo ""
        echo "[WARN] Update 006 failed (rc=$rc); starting rollback"
        rollback_update
        echo "[ERROR] Update 006 aborted"
    fi
    exit $rc
}

rollback_update() {

    if [[ "$CODE_BACKUP_DONE" -eq 1 && -f "$BACKUP_DIR/code-before.tar.gz" ]]; then
        tar -xzf "$BACKUP_DIR/code-before.tar.gz" -C / || warn "code restore failed"
        ok "Code tree restored"
    fi

    if [[ -f "$BACKUP_DIR/config.py.before" ]]; then
        cp -a "$BACKUP_DIR/config.py.before" "$CONFIG_FILE" || warn "config restore failed"
        ok "API config restored"
    fi

    if [[ "$DB_BACKUP_DONE" -eq 1 && -f "$BACKUP_DIR/dnsapproval-before.dump" ]]; then
        sudo -u postgres pg_restore --clean --if-exists \
            -d "$DB_NAME" "$BACKUP_DIR/dnsapproval-before.dump" \
            >/dev/null 2>&1 || warn "dnsapproval restore reported errors"
        ok "Portal database restored"
    fi

    systemctl restart portal-api.service >/dev/null 2>&1 || true
}

trap on_error EXIT

log "$UPDATE_NAME"

###############################################################################
# Preflight
###############################################################################

[[ $EUID -eq 0 ]] || fail "This update must be run as root"

for cmd in base64 curl pg_dump psql python3 systemctl tar; do
    command -v "$cmd" >/dev/null 2>&1 \
        || fail "Required command not found: $cmd"
done

[[ -f "$CONFIG_FILE" ]] || fail "File not found: $CONFIG_FILE"
[[ -d "$WEB_DIR" ]] || fail "Directory not found: $WEB_DIR"
[[ -f "$VERSION_FILE" ]] || fail "Update state file not found: $VERSION_FILE"
[[ -f "$API_DIR/main.py" ]] || fail "File not found: $API_DIR/main.py"

CURRENT_UPDATE="$(tr -d '[:space:]' < "$VERSION_FILE")"

if [[ ! "$CURRENT_UPDATE" =~ ^[0-9]+$ ]]; then
    fail "Invalid installed update level: $CURRENT_UPDATE"
fi

if (( CURRENT_UPDATE >= 6 )); then
    ok "Update 006 is already applied (level $CURRENT_UPDATE)"
    exit 0
fi

if (( CURRENT_UPDATE < 5 )); then
    fail "This update requires update level 5 (found $CURRENT_UPDATE). Apply the earlier updates first."
fi

ok "Installed update level: $CURRENT_UPDATE"

###############################################################################
# Validate the current Portal source
#
# Update 006 replaces main.py with the provider-layered version.
# The level-5 main.py contains the four direct Technitium
# block/unblock call sites; if they are missing, or the provider
# layer is already present, this install has drifted from the
# release chain and must not be overwritten silently.
###############################################################################

log "VALIDATING CURRENT FILES"

MAIN_TEXT="$(cat "$API_DIR/main.py")"

if grep -q 'api/blocked/add' <<<"$MAIN_TEXT" \
    && grep -q 'api/blocked/delete' <<<"$MAIN_TEXT"; then
    ok "main.py source validated (level-5 call sites present)"
else
    fail "main.py does not match the level-5 release (Technitium call sites missing). Refusing to replace it."
fi

if grep -q 'from providers import get_provider' <<<"$MAIN_TEXT"; then
    fail "main.py already contains the provider layer; this is not a level-5 main.py"
fi

ok "Provider layer not yet installed"

###############################################################################
# Stage + backups
###############################################################################

STAGE_DIR="$(mktemp -d /tmp/portal-update006.XXXXXX)"
BACKUP_DIR="$BACKUP_ROOT/update006-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

PAYLOAD_B64="$STAGE_DIR/update006-payload.tar.gz.b64"
PAYLOAD_TGZ="$STAGE_DIR/update006-payload.tar.gz"

log "BACKING UP CURRENT STATE"

# providers/ is NEW in this update: it does not exist on a
# portal that is still at update level 5.

BACKUP_PATHS=""
for _path in \
    opt/portal/api/main.py \
    opt/portal/api/providers
do
    [[ -e "/$_path" ]] && BACKUP_PATHS="$BACKUP_PATHS $_path"
done

[[ -n "$BACKUP_PATHS" ]] \
    || fail "nothing to back up"

tar -czf "$BACKUP_DIR/code-before.tar.gz" \
    -C / $BACKUP_PATHS 2>/dev/null \
    || fail "code backup failed"
CODE_BACKUP_DONE=1
ok "Code tree backed up"

cp -a "$CONFIG_FILE" "$BACKUP_DIR/config.py.before"
ok "API config backed up"

sudo -u postgres pg_dump -Fc -d "$DB_NAME" > "$BACKUP_DIR/dnsapproval-before.dump" \
    || fail "portal database backup failed"
DB_BACKUP_DONE=1
ok "Portal database backed up"

###############################################################################
# Payload
###############################################################################

log "STAGING UPDATE 006 PAYLOAD"

cat > "$PAYLOAD_B64" <<'UPDATE006_PAYLOAD_B64'
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
kABIAwA=
UPDATE006_PAYLOAD_B64

[[ "$(sha256sum "$PAYLOAD_B64" | awk '{print $1}')" == "dd91aded813628bc8575c4210e10853461480f06998f9ff784ffd220ae5ddf82" ]] \
    || fail "Embedded Update 006 payload checksum mismatch"

base64 -d "$PAYLOAD_B64" > "$PAYLOAD_TGZ"

[[ "$(sha256sum "$PAYLOAD_TGZ" | awk '{print $1}')" == "8ddf305e0cac79c46826688b6a3e8855da63d804285239a936b85e39c8980c8b" ]] \
    || fail "Decoded Update 006 payload checksum mismatch"

tar -tzf "$PAYLOAD_TGZ" > "$STAGE_DIR/payload-files.txt"

[[ "$(wc -l < "$STAGE_DIR/payload-files.txt")" -eq 5 ]] \
    || fail "Update 006 payload must contain exactly 5 files"

if grep -v -E '^api/(main\.py|providers/(base|technitium|firewall|__init__)\.py)$' \
    "$STAGE_DIR/payload-files.txt" | grep -q .; then
    fail "Unexpected path detected in Update 006 payload"
fi

ok "Update 006 payload staged and verified (5 files)"

###############################################################################
# Install provider package + provider-layered main.py
###############################################################################

log "INSTALLING UPDATE 006 RUNTIME FILES"

tar -xzf "$PAYLOAD_TGZ" -C "$PORTAL_DIR/" \
    || fail "payload extraction failed"

[[ -f "$API_DIR/providers/base.py" ]] || fail "providers/base.py was not installed"
[[ -f "$API_DIR/providers/technitium.py" ]] || fail "providers/technitium.py was not installed"
[[ -f "$API_DIR/providers/firewall.py" ]] || fail "providers/firewall.py was not installed"
[[ -f "$API_DIR/providers/__init__.py" ]] || fail "providers/__init__.py was not installed"
[[ -f "$API_DIR/main.py" ]] || fail "main.py was not installed"

rm -rf "$API_DIR/providers/__pycache__"

ok "Provider package installed"
ok "Provider-layered main.py installed"

###############################################################################
# API config: Firewall Appliance placeholder keys
#
# providers/firewall.py imports FIREWALL_API_URL and
# FIREWALL_API_TOKEN from config.py. Deployment option 2
# installs replace these with real appliance values; option 1
# deployments never select the firewall provider, so the
# placeholders are never used.
###############################################################################

log "ENSURING API CONFIGURATION"

python3 - "$CONFIG_FILE" <<'PYFIREWALLPLACEHOLDER' || fail "config patch failed"
import sys

config_file = sys.argv[1]

with open(config_file, "r", encoding="utf-8") as handle:
    content = handle.read()

if "FIREWALL_API_URL" not in content:
    if content and not content.endswith("\n"):
        content += "\n"
    content += (
        "\n"
        "# NetFortress Firewall Appliance (deployment option 2)\n"
        'FIREWALL_API_URL = "http://127.0.0.1:8080"\n'
        'FIREWALL_API_TOKEN = ""\n'
    )
    with open(config_file, "w", encoding="utf-8") as handle:
        handle.write(content)
    print("[ OK ] Firewall Appliance placeholder keys added to API config")
else:
    print("[ OK ] Firewall Appliance keys already present")
PYFIREWALLPLACEHOLDER

###############################################################################
# Database: ensure the provider setting exists
#
# The deployment launcher records the chosen architecture at
# install time. Existing installs may predate the launcher, so
# the key is created with the technitium default if missing -
# never overriding an existing choice.
###############################################################################

log "ENSURING PROVIDER SETTING"

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" >/dev/null <<SQL || fail "provider setting failed"
INSERT INTO portal_settings (setting_key, setting_value)
VALUES ('dns_provider', 'technitium')
ON CONFLICT (setting_key)
DO NOTHING;
SQL

ok "Provider setting present (default: technitium)"

###############################################################################
# Syntax verification
###############################################################################

log "VERIFYING UPDATE 006"

python3 - <<'PYSYNTAX' || fail "syntax verification failed"
import ast

paths = [
    "/opt/portal/api/main.py",
    "/opt/portal/api/providers/base.py",
    "/opt/portal/api/providers/technitium.py",
    "/opt/portal/api/providers/firewall.py",
    "/opt/portal/api/providers/__init__.py",
]

for path in paths:
    with open(path, "r", encoding="utf-8") as handle:
        ast.parse(handle.read(), filename=path)

print("[ OK ] Python syntax valid (main.py + providers package)")
PYSYNTAX

ok "Python syntax valid"

###############################################################################
# Restart + provider smoke test
###############################################################################

log "RESTARTING PORTAL API"

systemctl restart portal-api.service

API_READY=0

for i in {1..45}; do
    if curl -fsS --max-time 2 \
        http://127.0.0.1:8000/openapi.json \
        >/dev/null 2>&1; then
        API_READY=1
        break
    fi
    sleep 2
done

if [[ "$API_READY" -ne 1 ]]; then
    journalctl -u portal-api.service -n 50 --no-pager || true
    fail "Portal API did not become ready after Update 006"
fi

ok "Portal API is running"

"$API_DIR/venv/bin/python" - <<'PYPROVIDER' || fail "provider smoke test failed"
import sys

sys.path.insert(0, "/opt/portal/api")

from providers import active_provider_name, get_provider
from providers.base import NetworkServiceProvider

name = active_provider_name()
provider = get_provider()

if not isinstance(provider, NetworkServiceProvider):
    raise SystemExit("provider does not implement the base interface")

if provider.name != name:
    raise SystemExit("registry returned a provider that does not match the setting")

print("[ OK ] Active provider: %s" % name)
PYPROVIDER

ok "Provider registry verified"

###############################################################################
# Complete
###############################################################################

printf '%s\n' "6" > "$VERSION_FILE"
chmod 644 "$VERSION_FILE"

rm -rf "$STAGE_DIR"

log "UPDATE 006 COMPLETE"

echo ""
echo "Installed update level: 6"
echo "Backups:                $BACKUP_DIR"
echo ""
echo "Notes:"
echo "  - Block/unblock workflows now route through the active"
echo "    network services provider (portal_settings.dns_provider)."
echo "  - Option 1 (Technitium) deployments behave exactly as before."
echo "  - Option 2 (NetFortress Firewall Appliance) deployments are"
echo "    configured by the deployment launcher."
