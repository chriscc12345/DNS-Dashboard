#!/usr/bin/env bash
set -Eeuo pipefail

UPDATE_NAME="Update 002 - User Management and Initial Administrator Setup"

API_FILE="/opt/portal/api/main.py"
USERS_FILE="/opt/portal/web/users.php"
LOGIN_FILE="/opt/portal/web/login.php"
SETUP_FILE="/opt/portal/web/setup.php"

DB_NAME="dnsapproval"

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

log "$UPDATE_NAME"

[[ $EUID -eq 0 ]] \
    || fail "This update must be run as root"

[[ -f "$API_FILE" ]] \
    || fail "File not found: $API_FILE"

[[ -f "$USERS_FILE" ]] \
    || fail "File not found: $USERS_FILE"

[[ -f "$LOGIN_FILE" ]] \
    || fail "File not found: $LOGIN_FILE"

command -v psql >/dev/null 2>&1 \
    || fail "PostgreSQL client not found"

###############################################################################
# Database validation
###############################################################################

log "VALIDATING PORTAL DATABASE"

UNASSIGNED_COUNT="$(
    sudo -u postgres psql \
        -d "$DB_NAME" \
        -At \
        -c "
            SELECT COUNT(*)
            FROM groups
            WHERE LOWER(group_name) = LOWER('Unassigned');
        "
)"

[[ "$UNASSIGNED_COUNT" =~ ^[0-9]+$ ]] \
    || fail "Unable to validate Unassigned group"

if [[ "$UNASSIGNED_COUNT" -gt 1 ]]; then
    fail "Multiple groups named Unassigned already exist"
fi

if [[ "$UNASSIGNED_COUNT" -eq 1 ]]; then

    UNASSIGNED_PERMISSION_COUNT="$(
        sudo -u postgres psql \
            -d "$DB_NAME" \
            -At \
            -c "
                SELECT COUNT(*)
                FROM group_permissions gp
                JOIN groups g
                    ON g.id = gp.group_id
                WHERE LOWER(g.group_name) = LOWER('Unassigned');
            "
    )"

    [[ "$UNASSIGNED_PERMISSION_COUNT" =~ ^[0-9]+$ ]] \
        || fail "Unable to validate Unassigned permissions"

    if [[ "$UNASSIGNED_PERMISSION_COUNT" -ne 0 ]]; then
        fail "Existing Unassigned group has permissions assigned"
    fi

    ok "Existing Unassigned group has zero permissions"

else

    ok "Unassigned group does not exist and will be created"

fi

###############################################################################
# Detect conflicting case-insensitive group assignments
###############################################################################

CONFLICT_COUNT="$(
    sudo -u postgres psql \
        -d "$DB_NAME" \
        -At \
        -c "
            SELECT COUNT(*)
            FROM (
                SELECT LOWER(username)
                FROM user_groups
                GROUP BY LOWER(username)
                HAVING COUNT(DISTINCT group_id) > 1
            ) conflicts;
        "
)"

[[ "$CONFLICT_COUNT" =~ ^[0-9]+$ ]] \
    || fail "Unable to validate duplicate user group assignments"

if [[ "$CONFLICT_COUNT" -ne 0 ]]; then
    fail "Conflicting case-insensitive user group assignments detected"
fi

ok "No conflicting case-insensitive group assignments detected"
###############################################################################
# Cleanup and runtime rollback
###############################################################################

STAGE_DIR=""
BACKUP_DIR=""
SETUP_EXISTED=0
RUNTIME_INSTALL_STARTED=0
RUNTIME_INSTALL_COMPLETE=0

on_exit() {
    local rc=$?

    trap - EXIT

    # Rollback must continue even if an individual restore command fails.
    set +e

    if [[ "$rc" -ne 0 && "$RUNTIME_INSTALL_STARTED" -eq 1 && -n "$BACKUP_DIR" ]]; then
        warn "Update 002 failed after runtime installation started"
        warn "Restoring runtime files from backup"

        [[ -f "$BACKUP_DIR/main.py" ]] &&
            cp -a "$BACKUP_DIR/main.py" "$API_FILE"

        [[ -f "$BACKUP_DIR/users.php" ]] &&
            cp -a "$BACKUP_DIR/users.php" "$USERS_FILE"

        [[ -f "$BACKUP_DIR/login.php" ]] &&
            cp -a "$BACKUP_DIR/login.php" "$LOGIN_FILE"

        if [[ "$SETUP_EXISTED" -eq 1 ]]; then
            [[ -f "$BACKUP_DIR/setup.php" ]] &&
                cp -a "$BACKUP_DIR/setup.php" "$SETUP_FILE"
        else
            rm -f "$SETUP_FILE"
        fi

        systemctl restart portal-api.service >/dev/null 2>&1 || true

        warn "Runtime files restored from: $BACKUP_DIR"
        warn "Database safety changes may remain and are safe to re-run"
    fi

    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR"
    fi

    exit "$rc"
}

trap on_exit EXIT
###############################################################################
# Stage and validate Update 002 runtime files
###############################################################################

log "STAGING UPDATE 002 RUNTIME FILES"

for cmd in patch python3 php base64 gzip sha256sum tar awk stat install systemctl sudo; do
    command -v "$cmd" >/dev/null 2>&1 \
        || fail "Required command not found: $cmd"
done

STAGE_DIR="$(mktemp -d /tmp/portal-update-002.XXXXXX)"
chmod 700 "$STAGE_DIR"

STAGED_API="$STAGE_DIR/main.py"
STAGED_USERS="$STAGE_DIR/users.php"
STAGED_LOGIN="$STAGE_DIR/login.php"
STAGED_SETUP="$STAGE_DIR/setup.php"

cp -a "$API_FILE" "$STAGED_API"
cp -a "$USERS_FILE" "$STAGED_USERS"
cp -a "$LOGIN_FILE" "$STAGED_LOGIN"

ok "Runtime files copied to staging directory"
log "VALIDATING UPDATE 002 PAYLOAD"

PAYLOAD_B64="$STAGE_DIR/update002-payload.tar.gz.b64"
PAYLOAD_TGZ="$STAGE_DIR/update002-payload.tar.gz"
PAYLOAD_DIR="$STAGE_DIR/payload"

mkdir -p "$PAYLOAD_DIR"

cat > "$PAYLOAD_B64" <<'UPDATE002_PAYLOAD_B64'
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
UPDATE002_PAYLOAD_B64

[[ "$(sha256sum "$PAYLOAD_B64" | awk '{print $1}')" == \
"19602673980f01d459215d1ad88a49014d482ed798e080f8e345a08703d6e721" ]] \
    || fail "Embedded Update 002 payload checksum mismatch"

base64 -d "$PAYLOAD_B64" > "$PAYLOAD_TGZ"

[[ "$(sha256sum "$PAYLOAD_TGZ" | awk '{print $1}')" == \
"9be424dc3010e958b072cf23bb8b4ae3beafc825b7417a204d31b6369ace7995" ]] \
    || fail "Decoded Update 002 payload checksum mismatch"

tar -xzf "$PAYLOAD_TGZ" -C "$PAYLOAD_DIR"

[[ "$(sha256sum "$PAYLOAD_DIR/main-update002-real.patch" | awk '{print $1}')" == \
"be43ae3bbf72dc99d630fd63f6fd84f123ac55d4ce12261b304ed3f624db78dc" ]] \
    || fail "main.py patch checksum mismatch"

[[ "$(sha256sum "$PAYLOAD_DIR/users-update002.patch" | awk '{print $1}')" == \
"725b367cb1ea06cde0f65ed5a59feca2db227baa35ebc539ff81e0a1656a7d69" ]] \
    || fail "users.php patch checksum mismatch"

[[ "$(sha256sum "$PAYLOAD_DIR/login-update002.patch" | awk '{print $1}')" == \
"96e9ea541449ed8ea652211b8f2784890a8c81760d574d91ed56d2f78dffacab" ]] \
    || fail "login.php patch checksum mismatch"

[[ "$(sha256sum "$PAYLOAD_DIR/setup.php.gz.b64" | awk '{print $1}')" == \
"3310de42807c00a6da86f9199e1331bfb816af1845b79e7978c3f2e9a0922755" ]] \
    || fail "setup.php payload checksum mismatch"

log "PATCHING STAGED RUNTIME FILES"

patch --batch --fuzz=0 "$STAGED_API" < "$PAYLOAD_DIR/main-update002-real.patch"
patch --batch --fuzz=0 "$STAGED_USERS" < "$PAYLOAD_DIR/users-update002.patch"
patch --batch --fuzz=0 "$STAGED_LOGIN" < "$PAYLOAD_DIR/login-update002.patch"

base64 -d "$PAYLOAD_DIR/setup.php.gz.b64" \
    | gzip -dc > "$STAGED_SETUP"

python3 -m py_compile "$STAGED_API"
php -l "$STAGED_USERS" >/dev/null
php -l "$STAGED_LOGIN" >/dev/null
php -l "$STAGED_SETUP" >/dev/null

[[ "$(sha256sum "$STAGED_API" | awk '{print $1}')" == \
"bdfa84c260c34f0c1dd874df745e02890b69b053ed7b58a8682971b2b6f347a6" ]] \
    || fail "Staged main.py does not match tested Update 002 output"

[[ "$(sha256sum "$STAGED_USERS" | awk '{print $1}')" == \
"e295bd284acf2396e0f3328ec805e1b3d67ab75bcee3e276d182affcc4d1ead0" ]] \
    || fail "Staged users.php does not match tested Update 002 output"

[[ "$(sha256sum "$STAGED_LOGIN" | awk '{print $1}')" == \
"cae13aaaf1ec06d342924d4bba52823d40ab5e885c8ce6d0e567289074e0425e" ]] \
    || fail "Staged login.php does not match tested Update 002 output"

[[ "$(sha256sum "$STAGED_SETUP" | awk '{print $1}')" == \
"64d929fe8f5cf73ef86de8a2ffcf59bee766cae7794b3028977517ff2c6e993d" ]] \
    || fail "Staged setup.php does not match tested Update 002 output"

ok "All Update 002 runtime files staged and verified"
###############################################################################
# Backup
###############################################################################

log "BACKING UP CURRENT PORTAL RUNTIME"

BACKUP_DIR="/var/backups/portal/update-002-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

cp -a "$API_FILE" "$BACKUP_DIR/main.py"
cp -a "$USERS_FILE" "$BACKUP_DIR/users.php"
cp -a "$LOGIN_FILE" "$BACKUP_DIR/login.php"

SETUP_EXISTED=0

if [[ -f "$SETUP_FILE" ]]; then
    SETUP_EXISTED=1
    cp -a "$SETUP_FILE" "$BACKUP_DIR/setup.php"
fi

WEB_UID="$(stat -c '%u' "$USERS_FILE")"
WEB_GID="$(stat -c '%g' "$USERS_FILE")"
WEB_MODE="$(stat -c '%a' "$USERS_FILE")"

ok "Backup created: $BACKUP_DIR"
###############################################################################
# Database changes
#
# This stage intentionally runs after runtime source validation so an
# incompatible runtime source cannot leave the database partially updated.
###############################################################################

log "APPLYING DATABASE CHANGES"

sudo -u postgres psql \
    -v ON_ERROR_STOP=1 \
    -d "$DB_NAME" <<'SQL'

BEGIN;

INSERT INTO groups
(
    group_name,
    description
)
SELECT
    'Unassigned',
    'Unassigned'
WHERE NOT EXISTS
(
    SELECT 1
    FROM groups
    WHERE LOWER(group_name) = LOWER('Unassigned')
);

DELETE FROM user_groups ug
USING user_profiles up
WHERE LOWER(up.username) = LOWER(ug.username)
  AND ug.username <> up.username
  AND EXISTS
  (
      SELECT 1
      FROM user_groups keep_ug
      WHERE keep_ug.username = up.username
        AND keep_ug.group_id = ug.group_id
  );

COMMIT;

SQL

ok "Unassigned group verified/created"
ok "Safe historical duplicate cleanup completed"
###############################################################################
# Install staged runtime files
###############################################################################

log "INSTALLING UPDATE 002 RUNTIME FILES"

RUNTIME_INSTALL_STARTED=1

cp -a "$STAGED_API" "$API_FILE"
cp -a "$STAGED_USERS" "$USERS_FILE"
cp -a "$STAGED_LOGIN" "$LOGIN_FILE"

install \
    -o "$WEB_UID" \
    -g "$WEB_GID" \
    -m "$WEB_MODE" \
    "$STAGED_SETUP" \
    "$SETUP_FILE"

python3 -m py_compile "$API_FILE"
php -l "$USERS_FILE" >/dev/null
php -l "$LOGIN_FILE" >/dev/null
php -l "$SETUP_FILE" >/dev/null

systemctl restart portal-api.service
systemctl is-active --quiet portal-api.service \
    || fail "portal-api.service failed after Update 002"

[[ "$(sha256sum "$API_FILE" | awk '{print $1}')" == \
"bdfa84c260c34f0c1dd874df745e02890b69b053ed7b58a8682971b2b6f347a6" ]] \
    || fail "Installed main.py checksum verification failed"

[[ "$(sha256sum "$USERS_FILE" | awk '{print $1}')" == \
"e295bd284acf2396e0f3328ec805e1b3d67ab75bcee3e276d182affcc4d1ead0" ]] \
    || fail "Installed users.php checksum verification failed"

[[ "$(sha256sum "$LOGIN_FILE" | awk '{print $1}')" == \
"cae13aaaf1ec06d342924d4bba52823d40ab5e885c8ce6d0e567289074e0425e" ]] \
    || fail "Installed login.php checksum verification failed"

[[ "$(sha256sum "$SETUP_FILE" | awk '{print $1}')" == \
"64d929fe8f5cf73ef86de8a2ffcf59bee766cae7794b3028977517ff2c6e993d" ]] \
    || fail "Installed setup.php checksum verification failed"

RUNTIME_INSTALL_COMPLETE=1

ok "Update 002 runtime files installed"
ok "portal-api.service restarted successfully"
# Final Update 002 verification
###############################################################################

log "VERIFYING UPDATE 002"

UNASSIGNED_COUNT="$(
    sudo -u postgres psql \
        -At \
        -d "$DB_NAME" \
        -c "
            SELECT COUNT(*)
            FROM groups
            WHERE LOWER(group_name) = LOWER('Unassigned');
        "
)"

[[ "$UNASSIGNED_COUNT" =~ ^[0-9]+$ ]] \
    || fail "Unable to verify Unassigned group"

[[ "$UNASSIGNED_COUNT" -eq 1 ]] \
    || fail "Expected exactly one Unassigned group"

UNASSIGNED_PERMISSION_COUNT="$(
    sudo -u postgres psql \
        -At \
        -d "$DB_NAME" \
        -c "
            SELECT COUNT(*)
            FROM group_permissions gp
            JOIN groups g ON g.id = gp.group_id
            WHERE LOWER(g.group_name) = LOWER('Unassigned');
        "
)"

[[ "$UNASSIGNED_PERMISSION_COUNT" =~ ^[0-9]+$ ]] \
    || fail "Unable to verify Unassigned permissions"

[[ "$UNASSIGNED_PERMISSION_COUNT" -eq 0 ]] \
    || fail "Unassigned group must have zero permissions"

CONFLICT_COUNT="$(
    sudo -u postgres psql \
        -At \
        -d "$DB_NAME" \
        -c "
            SELECT COUNT(*)
            FROM
            (
                SELECT LOWER(username)
                FROM user_groups
                GROUP BY LOWER(username)
                HAVING COUNT(DISTINCT group_id) > 1
            ) conflicts;
        "
)"

[[ "$CONFLICT_COUNT" =~ ^[0-9]+$ ]] \
    || fail "Unable to verify duplicate user group assignments"

[[ "$CONFLICT_COUNT" -eq 0 ]] \
    || fail "Conflicting case-insensitive user group assignments remain"

ok "Database verification completed"
ok "Runtime checksum verification completed"

log "UPDATE 002 COMPLETE"
ok "Update 002 installed successfully"
