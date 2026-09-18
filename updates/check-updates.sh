#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Portal Update Checker
###############################################################################

UPDATE_STATE_FILE="/var/lib/portal/update-version"

GITHUB_REPO="chriscc12345/DNS-Dashboard"
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

TEMP_DIR="$(mktemp -d /tmp/portal-update.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo
echo "======================================================================"
echo "CHECKING FOR PORTAL UPDATES"
echo "======================================================================"

###############################################################################
# Installed update level
###############################################################################

if [[ ! -f "$UPDATE_STATE_FILE" ]]; then
    echo "[ERROR] Update state file not found: $UPDATE_STATE_FILE"
    exit 1
fi

CURRENT_UPDATE="$(tr -d '[:space:]' < "$UPDATE_STATE_FILE")"

if [[ ! "$CURRENT_UPDATE" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid installed update level: $CURRENT_UPDATE"
    exit 1
fi

###############################################################################
# Obtain manifest
###############################################################################

if [[ -n "${PORTAL_UPDATE_MANIFEST:-}" ]]; then

    MANIFEST_FILE="$PORTAL_UPDATE_MANIFEST"

    if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo "[ERROR] Local update manifest not found: $MANIFEST_FILE"
        exit 1
    fi

    MANIFEST_DIR="$(cd "$(dirname "$MANIFEST_FILE")" && pwd)"

    echo "[INFO] Using local update manifest"

else

    MANIFEST_FILE="$TEMP_DIR/manifest.json"
    MANIFEST_URL="${GITHUB_RAW_BASE}/updates/manifest.json"

    echo "[INFO] Downloading update manifest from GitHub"

    if ! curl -fsSL \
        --connect-timeout 10 \
        --max-time 30 \
        "$MANIFEST_URL" \
        -o "$MANIFEST_FILE"; then

        echo "[WARN] Unable to retrieve update manifest from GitHub"
        echo "[WARN] Base installation remains installed"
        exit 0
    fi
fi

###############################################################################
# Validate manifest
###############################################################################

LATEST_UPDATE="$(
python3 - "$MANIFEST_FILE" <<'PY'
import json
import re
import sys

manifest_file = sys.argv[1]

try:
    with open(manifest_file, "r", encoding="utf-8") as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"Invalid manifest JSON: {exc}")

if not isinstance(data, dict):
    raise SystemExit("Manifest root must be an object")

if data.get("schema_version") != 1:
    raise SystemExit("Unsupported manifest schema")

latest = data.get("latest_update")
updates = data.get("updates")

if not isinstance(latest, int) or isinstance(latest, bool) or latest < 0:
    raise SystemExit("Invalid latest_update")

if not isinstance(updates, list):
    raise SystemExit("Invalid updates list")

versions = []

for entry in updates:
    if not isinstance(entry, dict):
        raise SystemExit("Invalid update entry")

    version = entry.get("version")
    name = entry.get("name")
    filename = entry.get("filename")
    sha256 = entry.get("sha256")

    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        raise SystemExit("Invalid update version")

    if not isinstance(name, str) or not name.strip():
        raise SystemExit(f"Invalid name for update {version}")

    expected_filename = f"update-{version:03d}.sh"

    if filename != expected_filename:
        raise SystemExit(
            f"Invalid filename for update {version}: "
            f"expected {expected_filename}"
        )

    if not isinstance(sha256, str) or not re.fullmatch(
        r"[0-9a-fA-F]{64}", sha256
    ):
        raise SystemExit(f"Invalid SHA256 for update {version}")

    versions.append(version)

if len(versions) != len(set(versions)):
    raise SystemExit("Duplicate update versions")

expected_versions = list(range(1, latest + 1))

if sorted(versions) != expected_versions:
    raise SystemExit(
        "Update versions must be sequential from 1 through latest_update"
    )

print(latest)
PY
)"

echo "Installed update level: $CURRENT_UPDATE"
echo "Latest update level:    $LATEST_UPDATE"

###############################################################################
# Compare versions
###############################################################################

if (( CURRENT_UPDATE > LATEST_UPDATE )); then
    echo "[WARN] Installed update level is newer than the published manifest"
    exit 0
fi

if (( CURRENT_UPDATE == LATEST_UPDATE )); then
    echo "[ OK ] Portal is up to date"
    exit 0
fi

echo "[INFO] Portal updates are available"

###############################################################################
# Apply updates sequentially
###############################################################################

for (( VERSION=CURRENT_UPDATE+1; VERSION<=LATEST_UPDATE; VERSION++ )); do

    UPDATE_INFO="$(
    python3 - "$MANIFEST_FILE" "$VERSION" <<'PY'
import json
import sys

manifest_file = sys.argv[1]
wanted_version = int(sys.argv[2])

with open(manifest_file, "r", encoding="utf-8") as f:
    data = json.load(f)

for entry in data["updates"]:
    if entry["version"] == wanted_version:
        print(entry["name"])
        print(entry["filename"])
        print(entry["sha256"].lower())
        raise SystemExit(0)

raise SystemExit(f"Update {wanted_version} not found")
PY
    )"

    UPDATE_NAME="$(printf '%s\n' "$UPDATE_INFO" | sed -n '1p')"
    UPDATE_FILE="$(printf '%s\n' "$UPDATE_INFO" | sed -n '2p')"
    EXPECTED_SHA256="$(printf '%s\n' "$UPDATE_INFO" | sed -n '3p')"

    LOCAL_UPDATE_FILE="$TEMP_DIR/$UPDATE_FILE"

    echo
    echo "----------------------------------------------------------------------"
    echo "Applying Update $VERSION: $UPDATE_NAME"
    echo "----------------------------------------------------------------------"

    ###########################################################################
    # Obtain update script
    ###########################################################################

    if [[ -n "${PORTAL_UPDATE_MANIFEST:-}" ]]; then

        SOURCE_UPDATE_FILE="$MANIFEST_DIR/$UPDATE_FILE"

        if [[ ! -f "$SOURCE_UPDATE_FILE" ]]; then
            echo "[ERROR] Update file not found: $SOURCE_UPDATE_FILE"
            exit 1
        fi

        cp "$SOURCE_UPDATE_FILE" "$LOCAL_UPDATE_FILE"

    else

        UPDATE_URL="${GITHUB_RAW_BASE}/updates/${UPDATE_FILE}"

        echo "[INFO] Downloading $UPDATE_FILE"

        if ! curl -fsSL \
            --connect-timeout 10 \
            --max-time 60 \
            "$UPDATE_URL" \
            -o "$LOCAL_UPDATE_FILE"; then

            echo "[ERROR] Failed to download $UPDATE_FILE"
            exit 1
        fi
    fi

    ###########################################################################
    # Verify SHA256
    ###########################################################################

    ACTUAL_SHA256="$(
        sha256sum "$LOCAL_UPDATE_FILE" |
        awk '{print $1}'
    )"

    if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
        echo "[ERROR] SHA256 verification failed for $UPDATE_FILE"
        echo "[ERROR] Expected: $EXPECTED_SHA256"
        echo "[ERROR] Actual:   $ACTUAL_SHA256"
        exit 1
    fi

    echo "[ OK ] SHA256 verified"

    ###########################################################################
    # Execute update
    ###########################################################################

    chmod 700 "$LOCAL_UPDATE_FILE"

    echo "[INFO] Executing $UPDATE_FILE"

    if ! bash "$LOCAL_UPDATE_FILE"; then
        echo "[ERROR] Update $VERSION failed"
        echo "[ERROR] Update level remains at $CURRENT_UPDATE"
        exit 1
    fi

    ###########################################################################
    # Record successful update
    ###########################################################################

    printf '%s\n' "$VERSION" > "${UPDATE_STATE_FILE}.tmp"
    chmod 644 "${UPDATE_STATE_FILE}.tmp"
    mv -f "${UPDATE_STATE_FILE}.tmp" "$UPDATE_STATE_FILE"

    CURRENT_UPDATE="$VERSION"

    echo "[ OK ] Update $VERSION completed successfully"
    echo "[ OK ] Installed update level is now $CURRENT_UPDATE"
done

echo
echo "[ OK ] All available Portal updates have been applied"
