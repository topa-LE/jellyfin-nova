#!/usr/bin/env bash
set -euo pipefail

# Jellyfin Nova startup integration for linuxserver/jellyfin.
# Requires a persistent Nova source directory mounted at /config/nova.

SOURCE_DIR="/config/nova"
WEB_DIR="/usr/share/jellyfin/web"
TARGET_DIR="${WEB_DIR}/nova"
INDEX_FILE="${WEB_DIR}/index.html"

log() {
    printf '[jellyfin-nova] %s\n' "$*"
}

if [[ ! -f "${SOURCE_DIR}/nova.css" ]]; then
    log "ERROR: Persistent Nova source not found."
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/spotlight/spotlight-loader.js" ]]; then
    log "ERROR: Persistent Spotlight loader not found."
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/navigation/home-loader.js" ]]; then
    log "ERROR: Persistent Home navigation loader not found."
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/login/login-loader.js" ]]; then
    log "ERROR: Persistent Login loader not found."
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/assets/jellyfin-logo.png" ]]; then
    log "ERROR: Persistent Jellyfin logo not found."
    exit 1
fi

if [[ ! -f "$INDEX_FILE" ]]; then
    log "ERROR: Jellyfin index.html not found."
    exit 1
fi

if [[ -L "$SOURCE_DIR" || -L "$TARGET_DIR" ]]; then
    log "ERROR: Refusing Nova source or target symlink."
    exit 1
fi

if [[ -e "$TARGET_DIR" && ! -d "$TARGET_DIR" ]]; then
    log "ERROR: Nova target is not a directory."
    exit 1
fi

if find "$SOURCE_DIR" -type l -print -quit | grep -q .; then
    log "ERROR: Symlink found in persistent Nova source."
    exit 1
fi

if [[ -d "$TARGET_DIR" ]] && find "$TARGET_DIR" -type l -print -quit | grep -q .; then
    log "ERROR: Symlink found in existing Nova target."
    exit 1
fi

STAGE_DIR="$(mktemp -d "${WEB_DIR}/.nova-stage.XXXXXXXX")"
PREVIOUS_DIR=""

cleanup() {
    local result=$?

    if [[ -n "${PREVIOUS_DIR:-}" && -d "$PREVIOUS_DIR" && ! -e "$TARGET_DIR" ]]; then
        if mv "$PREVIOUS_DIR" "$TARGET_DIR"; then
            log "Previous Nova installation restored."
        else
            log "ERROR: Previous Nova installation could not be restored."
            result=1
        fi
    fi

    if [[ -n "${STAGE_DIR:-}" && -d "$STAGE_DIR" ]]; then
        rm -rf -- "$STAGE_DIR"
    fi

    exit "$result"
}
trap cleanup EXIT

cp -R "${SOURCE_DIR}/." "$STAGE_DIR/"

# Jellyfin runs as an unprivileged user (abc in LinuxServer images).
# mktemp -d creates the staging directory with mode 700.
# Make the staged web assets accessible before activating them.
find "$STAGE_DIR" -type d -exec chmod 755 {} +
find "$STAGE_DIR" -type f -exec chmod a+r {} +

if [[ -d "$TARGET_DIR" ]]; then
    PREVIOUS_DIR="$(mktemp -d "${WEB_DIR}/.nova-previous.XXXXXXXX")"
    rmdir "$PREVIOUS_DIR"
    mv "$TARGET_DIR" "$PREVIOUS_DIR"
fi

if ! mv "$STAGE_DIR" "$TARGET_DIR"; then
    if [[ -n "$PREVIOUS_DIR" && -d "$PREVIOUS_DIR" ]]; then
        mv "$PREVIOUS_DIR" "$TARGET_DIR"
    fi
    log "ERROR: Could not activate Nova files."
    exit 1
fi

STAGE_DIR=""

if [[ -n "$PREVIOUS_DIR" && -d "$PREVIOUS_DIR" ]]; then
    rm -rf -- "$PREVIOUS_DIR"
fi

LOADER_TAG='<script src="nova/spotlight/spotlight-loader.js" data-nova-spotlight></script>'
LOGIN_TAG='<script src="nova/login/login-loader.js" data-nova-login></script>'
HOME_TAG='<script src="nova/navigation/home-loader.js" data-nova-home></script>'

if ! grep -Fq "$LOADER_TAG" "$INDEX_FILE"; then
    if ! grep -Fqi '</body>' "$INDEX_FILE"; then
        log "ERROR: Jellyfin index.html has no closing body tag."
        exit 1
    fi

    sed -i "s|</body>|${LOADER_TAG}</body>|I" "$INDEX_FILE"
fi

if ! grep -Fq "$LOGIN_TAG" "$INDEX_FILE"; then
    if ! grep -Fqi '</body>' "$INDEX_FILE"; then
        log "ERROR: Jellyfin index.html has no closing body tag."
        exit 1
    fi

    sed -i "s|</body>|${LOGIN_TAG}</body>|I" "$INDEX_FILE"
fi

if ! grep -Fq "$HOME_TAG" "$INDEX_FILE"; then
    if ! grep -Fqi '</body>' "$INDEX_FILE"; then
        log "ERROR: Jellyfin index.html has no closing body tag."
        exit 1
    fi

    sed -i "s|</body>|${HOME_TAG}</body>|I" "$INDEX_FILE"
fi

log "Nova restored successfully."
