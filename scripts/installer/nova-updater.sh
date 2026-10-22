#!/usr/bin/env bash
set -euo pipefail

# Jellyfin Nova updater
# Created by topa-LE
# Updates an existing LinuxServer Jellyfin Docker installation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/nova-installer.sh"
RAW_BASE="https://raw.githubusercontent.com/topa-LE/jellyfin-nova/main"

RELEASE_URL="https://github.com/topa-LE/jellyfin-nova/releases/download/nova-latest/jellyfin-nova-package.tar.gz"
CONTAINER="${NOVA_CONTAINER:-jellyfin}"
WEB_DIR="/usr/share/jellyfin/web"

if [[ ! -f "$INSTALLER" ]]; then
    echo "ERROR: Nova installer not found."
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this updater as root."
    exit 1
fi

for command in curl docker python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: Missing dependency: $command"
        exit 1
    fi
done

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERROR: Jellyfin container not found: $CONTAINER"
    exit 1
fi

image="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER")"

case "$image" in
    lscr.io/linuxserver/jellyfin|lscr.io/linuxserver/jellyfin:*)
        ;;
    *)
        echo "ERROR: Unsupported Jellyfin Docker image: $image"
        exit 1
        ;;
esac

if ! docker exec "$CONTAINER" test -f /config/nova/nova.css; then
    echo "ERROR: Existing persistent Nova installation not found."
    exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

ARCHIVE="${TEMP_DIR}/jellyfin-nova-package.tar.gz"

echo "===== JELLYFIN NOVA UPDATE ====="
echo "Container: $CONTAINER"
echo

echo "===== 1. DOWNLOAD ====="
curl -fL --retry 3 "$RELEASE_URL" -o "$ARCHIVE"

echo
echo "===== 2. FETCH CURRENT INSTALLATION SCRIPTS ====="
CURRENT_INSTALLER="${TEMP_DIR}/installer/nova-installer.sh"
CURRENT_UPDATER="${TEMP_DIR}/installer/nova-updater.sh"
CURRENT_HOOK_DIR="${TEMP_DIR}/docker"
mkdir -p "${TEMP_DIR}/installer"
mkdir -p "$CURRENT_HOOK_DIR"

curl -fsSL "${RAW_BASE}/scripts/installer/nova-installer.sh" -o "$CURRENT_INSTALLER"
curl -fsSL "${RAW_BASE}/scripts/installer/nova-updater.sh" -o "$CURRENT_UPDATER"
curl -fsSL "${RAW_BASE}/scripts/docker/nova-init.sh" -o "${CURRENT_HOOK_DIR}/nova-init.sh"

bash -n "$CURRENT_INSTALLER"
bash -n "$CURRENT_UPDATER"
bash -n "${CURRENT_HOOK_DIR}/nova-init.sh"

expected_hook_sha256="$(sed -n 's/^[[:space:]]*local expected_sha256="\([0-9a-f]\{64\}\)"/\1/p' "$CURRENT_INSTALLER")"
actual_hook_sha256="$(sha256sum "${CURRENT_HOOK_DIR}/nova-init.sh")"
actual_hook_sha256="${actual_hook_sha256%% *}"

if [[ -z "$expected_hook_sha256" || "$expected_hook_sha256" != "$actual_hook_sha256" ]]; then
    echo "ERROR: Installer and startup hook checksums do not match."
    exit 1
fi

echo "OK: Installer and startup hook checksums match."

echo
echo "===== 3. PACKAGE VALIDATION ====="
source "$CURRENT_INSTALLER"

validate_nova_package_before_docker "$ARCHIVE"

echo
echo "===== 4. UPDATE PERSISTENT STARTUP HOOK ====="
install_nova_docker_init_hook "$CONTAINER" "$TEMP_DIR/installer"

echo
echo "===== 5. INSTALL UPDATE ====="
install_nova_docker_package "$CONTAINER" "$ARCHIVE" "$WEB_DIR"

echo
echo "===== 6. UPDATE HTML INTEGRATION ====="
set_nova_docker_spotlight_index "$CONTAINER" "$WEB_DIR" install

echo
echo "===== 7. VERIFY INSTALLATION ====="
persistent_hash="$(docker exec "$CONTAINER" sha256sum /config/nova/nova.css)"
active_hash="$(docker exec "$CONTAINER" sha256sum "${WEB_DIR}/nova/nova.css")"

persistent_hash="${persistent_hash%% *}"
active_hash="${active_hash%% *}"

if [[ "$persistent_hash" != "$active_hash" ]]; then
    echo "ERROR: Persistent and active Nova CSS differ."
    exit 1
fi

echo "CSS SHA256: $active_hash"
echo "Persistent and active Nova CSS match."

echo
echo
echo "===== 8. UPDATE HOST INSTALLATION SCRIPTS ====="

SCRIPT_BACKUP_DIR="${TEMP_DIR}/script-backups"
mkdir -p "$SCRIPT_BACKUP_DIR"

UPDATER_TARGET="${SCRIPT_DIR}/nova-updater.sh"
INSTALLER_STAGE=""
UPDATER_STAGE=""

cleanup_script_stages() {
    if [[ -n "$INSTALLER_STAGE" ]]; then
        rm -f -- "$INSTALLER_STAGE"
    fi
    if [[ -n "$UPDATER_STAGE" ]]; then
        rm -f -- "$UPDATER_STAGE"
    fi
}

restore_nova_scripts() {
    local failed=0

    if ! cp -p -- "$SCRIPT_BACKUP_DIR/nova-installer.sh" "$INSTALLER"; then
        echo "CRITICAL: Nova installer rollback failed." >&2
        failed=1
    fi

    if ! cp -p -- "$SCRIPT_BACKUP_DIR/nova-updater.sh" "$UPDATER_TARGET"; then
        echo "CRITICAL: Nova updater rollback failed." >&2
        failed=1
    fi

    if ! cmp -s "$SCRIPT_BACKUP_DIR/nova-installer.sh" "$INSTALLER"; then
        echo "CRITICAL: Nova installer rollback verification failed." >&2
        failed=1
    fi

    if ! cmp -s "$SCRIPT_BACKUP_DIR/nova-updater.sh" "$UPDATER_TARGET"; then
        echo "CRITICAL: Nova updater rollback verification failed." >&2
        failed=1
    fi

    cleanup_script_stages
    return "$failed"
}

cp -p -- "$INSTALLER" "$SCRIPT_BACKUP_DIR/nova-installer.sh"
cp -p -- "$UPDATER_TARGET" "$SCRIPT_BACKUP_DIR/nova-updater.sh"

INSTALLER_STAGE="$(mktemp "${SCRIPT_DIR}/.nova-installer.XXXXXXXX")"
UPDATER_STAGE="$(mktemp "${SCRIPT_DIR}/.nova-updater.XXXXXXXX")"

if ! install -m 755 "$CURRENT_INSTALLER" "$INSTALLER_STAGE" ||
   ! install -m 755 "$CURRENT_UPDATER" "$UPDATER_STAGE" ||
   ! cmp -s "$CURRENT_INSTALLER" "$INSTALLER_STAGE" ||
   ! cmp -s "$CURRENT_UPDATER" "$UPDATER_STAGE" ||
   ! bash -n "$INSTALLER_STAGE" ||
   ! bash -n "$UPDATER_STAGE"; then
    cleanup_script_stages
    echo "ERROR: Nova script staging failed." >&2
    exit 1
fi

if ! mv -f -- "$INSTALLER_STAGE" "$INSTALLER" ||
   ! mv -f -- "$UPDATER_STAGE" "$UPDATER_TARGET" ||
   ! cmp -s "$CURRENT_INSTALLER" "$INSTALLER" ||
   ! cmp -s "$CURRENT_UPDATER" "$UPDATER_TARGET"; then
    echo "ERROR: Nova script update failed; restoring previous versions." >&2
    if ! restore_nova_scripts; then
        echo "CRITICAL: Manual recovery of Nova host scripts required." >&2
    fi
    exit 1
fi

INSTALLER_STAGE=""
UPDATER_STAGE=""

echo "OK: Host installer and updater updated and verified."
echo

echo "Jellyfin Nova update completed."
echo "Refresh the browser with Ctrl+Shift+R."
