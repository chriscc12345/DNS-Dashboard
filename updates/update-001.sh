#!/usr/bin/env bash
set -Eeuo pipefail

UPDATE_NAME="Update 001 - Case-insensitive User Profiles"

USERS_FILE="/opt/portal/web/users.php"
API_FILE="/opt/portal/api/main.py"

log() {
    echo
    echo "======================================================================"
    echo "$1"
    echo "======================================================================"
}

ok() {
    echo "[ OK ] $1"
}

fail() {
    echo "[ERROR] $1" >&2
    exit 1
}

log "$UPDATE_NAME"

[[ $EUID -eq 0 ]] || fail "This update must be run as root"
[[ -f "$USERS_FILE" ]] || fail "File not found: $USERS_FILE"
[[ -f "$API_FILE" ]] || fail "File not found: $API_FILE"

PHP_MAP_OLD="\$profileMap[\$profile['username']] = \$profile;"
PHP_LOOKUP_OLD="\$profileMap[\$user['username']]"

PHP_MAP_NEW="\$profileMap[strtolower(\$profile['username'])] = \$profile;"
PHP_LOOKUP_NEW="\$profileMap[strtolower(\$user['username'])]"

API_OLD="WHERE username = %s"
API_NEW="WHERE LOWER(username) = LOWER(%s)"

PHP_ALREADY=0
API_ALREADY=0

grep -Fq "$PHP_MAP_NEW" "$USERS_FILE" && PHP_ALREADY=1
grep -Fq "$API_NEW" "$API_FILE" && API_ALREADY=1

if [[ "$PHP_ALREADY" -eq 1 && "$API_ALREADY" -eq 1 ]]; then
    ok "Update 001 is already applied"
    exit 0
fi

log "VALIDATING CURRENT FILES"

if [[ "$PHP_ALREADY" -eq 0 ]]; then
    grep -Fq "$PHP_MAP_OLD" "$USERS_FILE" \
        || fail "Expected users.php profile-map source not found"

    PHP_LOOKUP_COUNT="$(
        grep -Fo "$PHP_LOOKUP_OLD" "$USERS_FILE" | wc -l
    )"

    [[ "$PHP_LOOKUP_COUNT" -eq 8 ]] \
        || fail "Expected 8 users.php profile lookups, found $PHP_LOOKUP_COUNT"

    ok "users.php source validated"
else
    ok "users.php portion already applied"
fi

if [[ "$API_ALREADY" -eq 0 ]]; then
    API_OLD_COUNT="$(
        sed -n '/@app.get("\/user-profiles\/{username}")/,/class UserProfileUpdate/p' \
            "$API_FILE" |
        grep -Fc "$API_OLD" || true
    )"

    [[ "$API_OLD_COUNT" -eq 1 ]] \
        || fail "Expected exactly 1 profile API lookup, found $API_OLD_COUNT"

    ok "FastAPI source validated"
else
    ok "FastAPI portion already applied"
fi

BACKUP_DIR="/var/backups/portal/update-001-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

cp -a "$USERS_FILE" "$BACKUP_DIR/users.php"
cp -a "$API_FILE" "$BACKUP_DIR/main.py"

ok "Backup created: $BACKUP_DIR"

log "APPLYING UPDATE"

if [[ "$PHP_ALREADY" -eq 0 ]]; then
    sed -i \
        "s/\\\$profileMap\\[\\\$profile\\['username'\\]\\] = \\\$profile;/\\\$profileMap[strtolower(\\\$profile['username'])] = \\\$profile;/" \
        "$USERS_FILE"

    sed -i \
        "s/\\\$profileMap\\[\\\$user\\['username'\\]\\]/\\\$profileMap[strtolower(\\\$user['username'])]/g" \
        "$USERS_FILE"

    ok "users.php patched"
fi

if [[ "$API_ALREADY" -eq 0 ]]; then
    sed -i \
        '/@app.get("\/user-profiles\/{username}")/,/class UserProfileUpdate/ s/WHERE username = %s/WHERE LOWER(username) = LOWER(%s)/' \
        "$API_FILE"

    ok "FastAPI profile lookup patched"
fi

log "VERIFYING UPDATE"

grep -Fq "$PHP_MAP_NEW" "$USERS_FILE" \
    || fail "users.php profile-map verification failed"

PHP_FINAL_COUNT="$(
    grep -Fo "$PHP_LOOKUP_NEW" "$USERS_FILE" | wc -l
)"

[[ "$PHP_FINAL_COUNT" -eq 8 ]] \
    || fail "Expected 8 updated profile lookups, found $PHP_FINAL_COUNT"

grep -Fq "$API_NEW" "$API_FILE" \
    || fail "FastAPI profile lookup verification failed"

php -l "$USERS_FILE" >/dev/null \
    || fail "PHP syntax validation failed"

python3 -m py_compile "$API_FILE" \
    || fail "Python syntax validation failed"

ok "PHP syntax valid"
ok "Python syntax valid"

log "RESTARTING PORTAL API"

systemctl restart portal-api.service \
    || fail "Unable to restart portal-api.service"

systemctl is-active --quiet portal-api.service \
    || fail "portal-api.service is not active"

ok "portal-api.service is active"

log "UPDATE 001 COMPLETE"

ok "Case-insensitive User Profile matching enabled"
ok "Case-insensitive User Profile lookup enabled"
