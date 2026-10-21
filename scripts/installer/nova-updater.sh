#!/usr/bin/env bash
set -euo pipefail

# Jellyfin Nova updater
# Created by topa-LE
# Updates an existing LinuxServer Jellyfin Docker installation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/nova-installer.sh"

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
echo "===== 2. PACKAGE VALIDATION ====="
source "$INSTALLER"

validate_nova_package_before_docker "$ARCHIVE"

echo
echo "===== 3. INSTALL UPDATE ====="
install_nova_docker_package "$CONTAINER" "$ARCHIVE" "$WEB_DIR"

echo
echo "===== 4. VERIFY INSTALLATION ====="
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
echo "Jellyfin Nova update completed."
echo "Refresh the browser with Ctrl+Shift+R."
