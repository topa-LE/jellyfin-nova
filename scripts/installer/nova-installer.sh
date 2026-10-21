#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Jellyfin Nova - Linux / macOS Installer / Uninstaller
# https://github.com/topa-LE/jellyfin-nova
# ==============================================================================

REPO="${NOVA_REPO:-topa-LE/jellyfin-nova}"
BRANCH="${NOVA_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
REPO_URL="https://github.com/${REPO}"

SPOTLIGHT_FILES=(
    "src/spotlight/spotlight.html"
    "src/spotlight/spotlight.css"
    "src/spotlight/spotlight-loader.js"
)

# Detect OS once at startup
OS="$(uname -s)"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

cyan="\033[0;36m"
green="\033[0;32m"
yellow="\033[0;33m"
red="\033[0;31m"
gray="\033[0;90m"
reset="\033[0m"

step() { echo -e "${cyan}  $*${reset}"; }
ok()   { echo -e "${green}  [+] $*${reset}"; }
warn() { echo -e "${yellow}  [!] $*${reset}"; }
fail() { echo -e "${red}  [X] $*${reset}"; }
skip() { echo -e "${gray}  [-] $*${reset}"; }
info() { echo -e "${gray}      $*${reset}"; }

exit_error() {
    echo ""
    [[ -n "${1:-}" ]] && fail "$1"
    read -rp "  Press Enter to exit: "
    exit 1
}

check_dependencies() {
    local missing=()
    for cmd in curl python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing required dependencies: ${missing[*]}"
        if [[ "$OS" == "Darwin" ]]; then
            info "Install them via Homebrew: brew install ${missing[*]}"
            info "Or install Xcode Command Line Tools: xcode-select --install"
        else
            info "Install them and re-run this script."
        fi
        exit 1
    fi
}

show_header() {
    clear
    echo ""
    echo -e "${cyan}  ================================================${reset}"
    echo -e "  Jellyfin Nova - $1"
    echo -e "${gray}  ${REPO_URL}${reset}"
    echo -e "${cyan}  ================================================${reset}"
    echo ""
}

# ------------------------------------------------------------------------------
# Detect Jellyfin Docker containers
# ------------------------------------------------------------------------------

find_jellyfin_docker_containers() {
    command -v docker >/dev/null 2>&1 || return 0
    docker info >/dev/null 2>&1 || return 0

    local container image
    while IFS='|' read -r container image; do
        case "$image" in
            jellyfin/jellyfin:*|jellyfin/jellyfin|lscr.io/linuxserver/jellyfin:*|lscr.io/linuxserver/jellyfin)
                printf '%s|%s\n' "$container" "$image"
                ;;
        esac
    done < <(docker ps --format '{{.Names}}|{{.Image}}')
}

# ------------------------------------------------------------------------------
# Select Jellyfin Docker container
# ------------------------------------------------------------------------------

select_jellyfin_docker_container() {
    local containers=()
    local entry choice

    while IFS= read -r entry; do
        [[ -n "$entry" ]] && containers+=("$entry")
    done < <(find_jellyfin_docker_containers)

    if [[ ${#containers[@]} -eq 0 ]]; then
        return 1
    fi

    if [[ ${#containers[@]} -eq 1 ]]; then
        printf '%s\n' "${containers[0]%%|*}"
        return 0
    fi

    echo "  Multiple Jellyfin Docker containers found:" >&2

    local i
    for i in "${!containers[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${containers[i]}" >&2
    done

    read -rp "  Select container number: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] ||
       (( 10#$choice < 1 || 10#$choice > ${#containers[@]} )); then
        warn "Invalid Docker container selection." >&2
        return 1
    fi

    printf '%s\n' "${containers[10#$choice-1]%%|*}"
}

# ------------------------------------------------------------------------------
# Locate Jellyfin web directory inside Docker
# ------------------------------------------------------------------------------

get_jellyfin_docker_web_dir() {
    local container="$1"
    local candidate

    [[ -n "$container" ]] || return 1

    for candidate in \
        /jellyfin/jellyfin-web \
        /usr/share/jellyfin/web \
        /usr/lib/jellyfin/web; do

        if docker exec "$container" test -f "$candidate/index.html" 2>/dev/null; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    warn "Jellyfin web directory not found inside container: $container" >&2
    return 1
}

# ------------------------------------------------------------------------------
# Detect available Jellyfin installation methods
# ------------------------------------------------------------------------------

detect_nova_install_method() {
    if [[ -n "${NOVA_WEB_DIR:-}" ]]; then
        printf '%s\n' "native"
        return 0
    fi

    local candidate
    local candidates=(
        "/usr/share/jellyfin/web"
        "/usr/lib/jellyfin/web"
        "/var/lib/jellyfin/web"
        "/opt/jellyfin/web"
        "/usr/local/share/jellyfin/web"
        "/opt/homebrew/share/jellyfin/web"
        "/opt/homebrew/opt/jellyfin/web"
        "/usr/local/opt/jellyfin/web"
        "/Applications/Jellyfin.app/Contents/Resources/jellyfin-web"
        "$HOME/Applications/Jellyfin.app/Contents/Resources/jellyfin-web"
        "/Applications/Jellyfin.app/Contents/Resources/web"
        "$HOME/Applications/Jellyfin.app/Contents/Resources/web"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}/index.html" ]]; then
            printf '%s\n' "native"
            return 0
        fi
    done

    if [[ -n "$(find_jellyfin_docker_containers)" ]]; then
        printf '%s\n' "docker"
        return 0
    fi

    printf '%s\n' "manual"
}

# ------------------------------------------------------------------------------
# Copy Nova files into a Jellyfin Docker container
# ------------------------------------------------------------------------------

copy_nova_to_docker() {
    local container="$1"
    local source_dir="$2"
    local web_dir="$3"
    local stage="${web_dir}/.nova-stage-$$"
    local previous="${web_dir}/.nova-previous-$$"
    local target="${web_dir}/nova"

    [[ -n "$container" && -d "$source_dir" && -n "$web_dir" ]] || return 1

    # Never overwrite recovery directories from an earlier failed attempt.
    if docker exec "$container" test -e "$stage" ||
       docker exec "$container" test -e "$previous"; then
        warn "Nova Docker staging or recovery directory already exists."
        return 1
    fi

    docker exec "$container" mkdir "$stage" || return 1

    if ! docker cp "${source_dir}/." "${container}:${stage}/"; then
        docker exec "$container" rm -rf -- "$stage" || true
        return 1
    fi

    if docker exec "$container" test -e "$target"; then
        if ! docker exec "$container" mv "$target" "$previous"; then
            docker exec "$container" rm -rf -- "$stage" || true
            return 1
        fi
    fi

    if ! docker exec "$container" mv "$stage" "$target"; then
        if docker exec "$container" test -d "$previous"; then
            docker exec "$container" mv "$previous" "$target" \
                || warn "Nova Docker web rollback failed; recovery retained."
        fi
        docker exec "$container" rm -rf -- "$stage" || true
        return 1
    fi

    if docker exec "$container" test -d "$previous"; then
        docker exec "$container" rm -rf -- "$previous" \
            || warn "Previous Nova Docker web directory retained."
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Install Nova package into a Jellyfin Docker container
# ------------------------------------------------------------------------------

validate_nova_package_before_docker() {
    local archive="$1"
    local temporary

    [[ -f "$archive" ]] || return 1

    temporary="$(mktemp -d)" || return 1

    if ! install_nova_package "$archive" "$temporary"; then
        rm -rf -- "$temporary"
        return 1
    fi

    rm -rf -- "$temporary"
    ok "Nova package validated before Docker changes."
}

install_nova_docker_init_hook() {
    local container="$1"
    local installer_dir="$2"
    local hook_file="${installer_dir}/../docker/nova-init.sh"
    local temporary_hook=""

    [[ -n "$container" ]] || return 1

    if [[ ! -f "$hook_file" ]]; then
        temporary_hook="$(mktemp)" || return 1
        hook_file="$temporary_hook"

        if ! curl -fsSL \
            "${RAW}/scripts/docker/nova-init.sh" \
            -o "$hook_file"; then
            rm -f -- "$temporary_hook"
            warn "Could not download Nova startup hook."
            return 1
        fi
    fi

    local expected_sha256="4a84c26e3f2cb0ed01871fb7ee7130c5d42740a60cb7a0e4ce3bdc0a2518a606"
    local actual_sha256

    if ! actual_sha256="$(python3 - "$hook_file" <<'PYHASH'
import hashlib
import sys

with open(sys.argv[1], "rb") as file:
    print(hashlib.file_digest(file, "sha256").hexdigest())
PYHASH
)"; then
        [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
        warn "Could not calculate Nova startup hook checksum."
        return 1
    fi

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
        warn "Nova startup hook checksum mismatch."
        return 1
    fi

    if ! bash -n "$hook_file"; then
        [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
        warn "Nova startup hook failed syntax validation."
        return 1
    fi

    if ! docker exec "$container" test -d /custom-cont-init.d; then
        [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
        warn "Persistent LinuxServer startup hook directory is missing."
        return 1
    fi

    local hook_target="/custom-cont-init.d/nova-init.sh"
    local hook_backup="/custom-cont-init.d/nova-init.sh.nova-backup"
    local existing_hook=0

    if docker exec "$container" test -L "$hook_target"; then
        warn "Refusing to overwrite a symlinked startup hook."
        [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
        return 1
    fi

    if docker exec "$container" test -e "$hook_target"; then
        if ! docker exec "$container" test -f "$hook_target"; then
            warn "Existing startup hook is not a regular file."
            [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
            return 1
        fi

        # Never overwrite an unrelated file occupying Nova's hook path.
        if ! docker exec "$container" grep -Fq -- \
            'Jellyfin Nova startup integration for linuxserver/jellyfin.' \
            "$hook_target"; then
            warn "Existing startup hook is not identified as Jellyfin Nova."
            [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
            return 1
        fi

        existing_hook=1

        if docker exec "$container" test -e "$hook_backup" ||
           docker exec "$container" test -L "$hook_backup"; then
            warn "Startup hook backup path already exists."
            [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
            return 1
        fi

        if ! docker exec "$container" cp -p -- "$hook_target" "$hook_backup"; then
            warn "Could not back up existing startup hook."
            [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
            return 1
        fi
    fi

    if ! docker cp "$hook_file" "${container}:${hook_target}" ||
       ! docker exec "$container" chmod 755 "$hook_target"; then
        warn "Could not install Nova startup hook."

        if [[ "$existing_hook" -eq 1 ]]; then
            if ! docker exec "$container" cp -p -- "$hook_backup" "$hook_target"; then
                warn "CRITICAL: Could not restore previous startup hook."
            fi
        else
            docker exec "$container" rm -f -- "$hook_target" || true
        fi

        [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
        return 1
    fi

    if [[ "$existing_hook" -eq 1 ]]; then
        if ! docker exec "$container" rm -f -- "$hook_backup"; then
            warn "Nova startup hook installed, but backup cleanup failed."
            [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"
            return 1
        fi
    fi

    [[ -z "$temporary_hook" ]] || rm -f -- "$temporary_hook"

    ok "Nova LinuxServer startup hook installed."
}


remove_nova_docker_init_hook() {
    local container="$1"
    local hook_path="/custom-cont-init.d/nova-init.sh"

    [[ -n "$container" ]] || return 1

    if docker exec "$container" test -L "$hook_path"; then
        warn "Refusing to remove a symlinked Nova startup hook."
        return 1
    fi

    if ! docker exec "$container" test -e "$hook_path"; then
        ok "Nova startup hook is already absent."
        return 0
    fi

    if ! docker exec "$container" test -f "$hook_path"; then
        warn "Nova startup hook path is not a regular file."
        return 1
    fi

    if ! docker exec "$container" rm -f -- "$hook_path"; then
        warn "Could not remove Nova startup hook."
        return 1
    fi

    ok "Nova LinuxServer startup hook removed."
}

install_nova_docker_package() {
    local container="$1"
    local archive="$2"
    local web_dir="$3"
    local staging

    [[ -n "$container" && -f "$archive" && -n "$web_dir" ]] || return 1

    staging="$(mktemp -d)" || return 1

    if ! mkdir -p "${staging}/web"; then
        rm -rf -- "$staging"
        return 1
    fi

    # Reuse the existing validated, atomic Nova package installer.
    if ! install_nova_package "$archive" "${staging}/web"; then
        rm -rf -- "$staging"
        return 1
    fi

    # Stage the validated package inside the persistent config volume.
    local persistent_stage="/config/.nova-stage-$$"
    local persistent_previous="/config/.nova-previous-$$"

    if ! docker exec "$container" mkdir "$persistent_stage"; then
        rm -rf -- "$staging"
        return 1
    fi

    if ! docker cp "${staging}/web/nova/." "${container}:${persistent_stage}/"; then
        docker exec "$container" rm -rf -- "$persistent_stage" || true
        rm -rf -- "$staging"
        return 1
    fi

    # Do not overwrite an existing recovery directory.
    if docker exec "$container" test -e "$persistent_previous"; then
        docker exec "$container" rm -rf -- "$persistent_stage" || true
        rm -rf -- "$staging"
        return 1
    fi

    if docker exec "$container" test -e /config/nova; then
        if ! docker exec "$container" mv /config/nova "$persistent_previous"; then
            docker exec "$container" rm -rf -- "$persistent_stage" || true
            rm -rf -- "$staging"
            return 1
        fi
    fi

    if ! docker exec "$container" mv "$persistent_stage" /config/nova; then
        if docker exec "$container" test -d "$persistent_previous"; then
            docker exec "$container" mv "$persistent_previous" /config/nova \
                || warn "Nova config rollback failed; recovery directory retained."
        fi
        docker exec "$container" rm -rf -- "$persistent_stage" || true
        rm -rf -- "$staging"
        return 1
    fi

    if ! copy_nova_to_docker "$container" "${staging}/web/nova" "$web_dir"; then
        warn "Nova web installation failed; restoring previous persistent config."

        local failed_dir="/config/.nova-failed-$$"

        if docker exec "$container" test -e "$failed_dir"; then
            warn "Rollback destination already exists; persistent config left unchanged."
        elif docker exec "$container" mv /config/nova "$failed_dir"; then
            if docker exec "$container" test -d "$persistent_previous"; then
                if docker exec "$container" mv "$persistent_previous" /config/nova; then
                    docker exec "$container" rm -rf -- "$failed_dir" \
                        || warn "Failed Nova staging directory could not be removed."
                    ok "Previous persistent Nova config restored."
                else
                    warn "Rollback failed; previous config retained at ${persistent_previous}."
                    docker exec "$container" mv "$failed_dir" /config/nova \
                        || warn "Failed Nova config retained at ${failed_dir}."
                fi
            else
                docker exec "$container" rm -rf -- "$failed_dir" \
                    || warn "Failed Nova staging directory could not be removed."
                ok "Failed new Nova config removed; no previous version existed."
            fi
        else
            warn "Could not isolate failed Nova config; manual recovery may be needed."
        fi

        rm -rf -- "$staging"
        return 1
    fi

    if docker exec "$container" test -d "$persistent_previous"; then
        docker exec "$container" rm -rf -- "$persistent_previous" \
            || warn "Previous Nova config directory could not be removed."
    fi

    rm -rf -- "$staging"
}

# ------------------------------------------------------------------------------
# Resolve Jellyfin Docker installation target
# ------------------------------------------------------------------------------

get_nova_docker_image_family() {
    local container="$1"
    local image

    [[ -n "$container" ]] || return 1

    image="$(docker inspect --format '{{.Config.Image}}' "$container")" \
        || return 1

    case "$image" in
        lscr.io/linuxserver/jellyfin|lscr.io/linuxserver/jellyfin:*)
            printf '%s\n' "linuxserver"
            ;;
        jellyfin/jellyfin|jellyfin/jellyfin:*)
            printf '%s\n' "official"
            ;;
        *)
            printf '%s\n' "unsupported"
            ;;
    esac
}

resolve_nova_docker_target() {
    local container web_dir

    container="$(select_jellyfin_docker_container)" || {
        warn "No Jellyfin Docker container selected." >&2
        return 1
    }

    web_dir="$(get_jellyfin_docker_web_dir "$container")" || return 1

    NOVA_DOCKER_CONTAINER="$container"
    NOVA_DOCKER_WEB_DIR="$web_dir"

    ok "Jellyfin Docker container: $container" >&2
    ok "Jellyfin Docker web directory: $web_dir" >&2
}

# ------------------------------------------------------------------------------
# Read and write Jellyfin files inside Docker
# ------------------------------------------------------------------------------

nova_docker_read_file() {
    local container="$1"
    local remote_file="$2"
    local local_file="$3"

    [[ -n "$container" && -n "$remote_file" && -n "$local_file" ]] || return 1

    docker cp "${container}:${remote_file}" "$local_file"
}

nova_docker_write_file() {
    local container="$1"
    local local_file="$2"
    local remote_file="$3"

    [[ -n "$container" && -f "$local_file" && -n "$remote_file" ]] || return 1

    docker cp "$local_file" "${container}:${remote_file}"
}

# ------------------------------------------------------------------------------
# Manage Spotlight index integration inside Docker
# ------------------------------------------------------------------------------

set_nova_docker_spotlight_index() {
    local container="$1"
    local web_dir="$2"
    local mode="$3"
    local staging local_index

    [[ -n "$container" && -n "$web_dir" ]] || return 1

    case "$mode" in
        install|uninstall) ;;
        *) return 1 ;;
    esac

    staging="$(mktemp -d)" || return 1
    local_index="${staging}/index.html"

    if ! nova_docker_read_file "$container" "${web_dir}/index.html" "$local_index"; then
        rm -rf -- "$staging"
        return 1
    fi

    if ! set_spotlight_index "$local_index" "$mode"; then
        rm -rf -- "$staging"
        return 1
    fi

    if ! nova_docker_write_file "$container" "$local_index" "${web_dir}/index.html"; then
        rm -rf -- "$staging"
        return 1
    fi

    rm -rf -- "$staging"
}

# ------------------------------------------------------------------------------
# Locate Jellyfin web directory
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Remove only manifest-listed Nova files from Docker
# ------------------------------------------------------------------------------

remove_nova_docker_package() {
    local container="$1"
    local archive="$2"
    local web_dir="$3"
    local manifest
    local relative_path

    [[ -n "$container" && -f "$archive" && -n "$web_dir" ]] || return 1

    manifest="$(mktemp)" || return 1

    if ! python3 - "$archive" > "$manifest" <<'NOVA_DOCKER_MANIFEST'
import pathlib
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as tar:
    members = tar.getmembers()
    files = [member for member in members if member.isfile()]
    names = [member.name.removeprefix("./") for member in files]

    if len(names) != 30 or len(set(names)) != 30:
        raise SystemExit("Unexpected Nova package manifest")

    if any(
        not name
        or pathlib.PurePosixPath(name).is_absolute()
        or ".." in pathlib.PurePosixPath(name).parts
        for name in names
    ):
        raise SystemExit("Unsafe Nova package path")

    if any(not (member.isfile() or member.isdir()) for member in members):
        raise SystemExit("Unsupported Nova package member")

    for name in names:
        print(name)
NOVA_DOCKER_MANIFEST
    then
        rm -f -- "$manifest"
        return 1
    fi

    # Verify the Nova root and every parent directory before deleting files.
    if ! docker exec "$container" test -d "${web_dir}/nova"; then
        rm -f -- "$manifest"
        return 0
    fi

    if docker exec "$container" test -L "${web_dir}/nova"; then
        rm -f -- "$manifest"
        warn "Refusing to remove files through a Nova symlink." >&2
        return 1
    fi

    while IFS= read -r relative_path; do
        local parent="${web_dir}/nova"
        local component
        local remainder="$relative_path"

        while [[ "$remainder" == */* ]]; do
            component="${remainder%%/*}"
            parent="${parent}/${component}"

            if docker exec "$container" test -L "$parent"; then
                rm -f -- "$manifest"
                warn "Refusing to follow a symlink: $parent" >&2
                return 1
            fi

            remainder="${remainder#*/}"
        done
    done < "$manifest"

    # All manifest paths have passed preflight checks.
    while IFS= read -r relative_path; do
        if ! docker exec "$container" rm -f -- "${web_dir}/nova/${relative_path}"; then
            rm -f -- "$manifest"
            return 1
        fi
    done < "$manifest"

    rm -f -- "$manifest"
}

# ------------------------------------------------------------------------------
# Inspect whether Jellyfin Docker web files are backed by a persistent mount
# ------------------------------------------------------------------------------

remove_nova_docker_persistent_package() {
    local container="$1"
    local archive="$2"
    local manifest
    local relative_path
    local root="/config/nova"

    [[ -n "$container" && -f "$archive" ]] || return 1

    manifest="$(mktemp)" || return 1

    if ! python3 - "$archive" > "$manifest" <<'NOVA_PERSISTENT_MANIFEST'
import pathlib
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as tar:
    members = tar.getmembers()
    files = [member for member in members if member.isfile()]
    names = [member.name.removeprefix("./") for member in files]

    if len(names) != 30 or len(set(names)) != 30:
        raise SystemExit("Unexpected Nova package manifest")

    if any(
        not name
        or pathlib.PurePosixPath(name).is_absolute()
        or ".." in pathlib.PurePosixPath(name).parts
        for name in names
    ):
        raise SystemExit("Unsafe Nova package path")

    if any(not (member.isfile() or member.isdir()) for member in members):
        raise SystemExit("Unsupported Nova package member")

    for name in names:
        print(name)
NOVA_PERSISTENT_MANIFEST
    then
        rm -f -- "$manifest"
        return 1
    fi

    if docker exec "$container" test -L "$root"; then
        rm -f -- "$manifest"
        warn "Refusing symlinked persistent Nova directory."
        return 1
    fi

    if ! docker exec "$container" test -e "$root"; then
        rm -f -- "$manifest"
        ok "Persistent Nova directory already absent."
        return 0
    fi

    if ! docker exec "$container" test -d "$root"; then
        rm -f -- "$manifest"
        warn "Persistent Nova path is not a directory."
        return 1
    fi

    while IFS= read -r relative_path; do
        local parent="$root"
        local component
        local remainder="$relative_path"

        while [[ "$remainder" == */* ]]; do
            component="${remainder%%/*}"
            parent="${parent}/${component}"

            if docker exec "$container" test -L "$parent"; then
                rm -f -- "$manifest"
                warn "Refusing symlinked directory: $parent"
                return 1
            fi

            remainder="${remainder#*/}"
        done
    done < "$manifest"

    while IFS= read -r relative_path; do
        if ! docker exec "$container" rm -f -- "${root}/${relative_path}"; then
            rm -f -- "$manifest"
            return 1
        fi
    done < "$manifest"

    rm -f -- "$manifest"
    ok "Persistent Nova package files removed."
}

check_nova_docker_init_persistence() {
    local container="$1"

    [[ -n "$container" ]] || return 1

    local mounts
    mounts="$(docker inspect --format '{{json .Mounts}}' "$container")" || return 1

    NOVA_DOCKER_MOUNTS="$mounts" python3 - <<'NOVA_DOCKER_INIT'
import json
import os
from pathlib import PurePosixPath

target = PurePosixPath("/custom-cont-init.d")
mounts = json.loads(os.environ["NOVA_DOCKER_MOUNTS"])

matches = []

for mount in mounts:
    destination = mount.get("Destination", "")
    if not destination:
        continue

    mounted_path = PurePosixPath(destination)

    if target == mounted_path or mounted_path in target.parents:
        matches.append(mount)

if not matches:
    raise SystemExit(
        "ERROR: /custom-cont-init.d has no persistent Docker mount."
    )

mount = max(
    matches,
    key=lambda item: len(PurePosixPath(item["Destination"]).parts)
)

if mount.get("RW") is not True:
    raise SystemExit(
        "ERROR: /custom-cont-init.d is mounted read-only."
    )

print("OK: Persistent Docker init-hook mount detected.")
print("TYPE:", mount.get("Type", "unknown"))
print("SOURCE:", mount.get("Source", "unknown"))
print("DESTINATION:", mount.get("Destination", "unknown"))
NOVA_DOCKER_INIT
}

check_nova_docker_config_persistence() {
    local container="$1"

    [[ -n "$container" ]] || return 1

    local mounts
    mounts="$(docker inspect --format '{{json .Mounts}}' "$container")" || return 1

    NOVA_DOCKER_MOUNTS="$mounts" python3 - <<'NOVA_DOCKER_CONFIG'
import json
import os
import pathlib

config = pathlib.PurePosixPath("/config")
mounts = json.loads(os.environ["NOVA_DOCKER_MOUNTS"])

matches = [
    mount for mount in mounts
    if mount.get("Destination")
    and (
        config == pathlib.PurePosixPath(mount["Destination"])
        or pathlib.PurePosixPath(mount["Destination"]) in config.parents
    )
]

if not matches:
    raise SystemExit("ERROR: Docker /config is not mounted persistently.")

mount = max(
    matches,
    key=lambda item: len(pathlib.PurePosixPath(item["Destination"]).parts)
)

if mount.get("RW") is not True:
    raise SystemExit("ERROR: Docker /config mount is read-only.")

print("OK: Persistent Docker config mount detected.")
print("TYPE:", mount.get("Type", "unknown"))
print("SOURCE:", mount.get("Source", "unknown"))
print("DESTINATION:", mount.get("Destination", "unknown"))
NOVA_DOCKER_CONFIG
}

check_nova_official_docker_persistence() {
    local container="$1"
    local web_dir="$2"

    [[ -n "$container" && -n "$web_dir" ]] || return 1

    if ! check_nova_docker_web_persistence "$container" "$web_dir"; then
        warn "Official Jellyfin Docker requires a persistent, writable web mount."
        return 1
    fi

    warn "Official Jellyfin web files are mounted persistently."
    warn "Jellyfin image updates do not automatically refresh mounted web files."
    warn "The web mount must be maintained alongside Jellyfin updates."

    return 0
}

check_nova_docker_web_persistence() {
    local container="$1"
    local web_dir="$2"

    [[ -n "$container" && -n "$web_dir" ]] || return 1

    local mounts
    mounts="$(docker inspect --format '{{json .Mounts}}' "$container")" || return 1

    NOVA_DOCKER_MOUNTS="$mounts" python3 - "$web_dir" <<'NOVA_DOCKER_PERSISTENCE'
import json
import os
import pathlib
import sys

web_dir = pathlib.PurePosixPath(sys.argv[1])
mounts = json.loads(os.environ["NOVA_DOCKER_MOUNTS"])

matches = []

for mount in mounts:
    destination = mount.get("Destination", "")
    if not destination:
        continue

    mounted_path = pathlib.PurePosixPath(destination)

    if web_dir == mounted_path or mounted_path in web_dir.parents:
        matches.append(mount)

if not matches:
    print("NOT_PERSISTENT: Jellyfin web directory is not covered by a Docker mount.")
    raise SystemExit(2)

match = max(
    matches,
    key=lambda item: len(pathlib.PurePosixPath(item["Destination"]).parts)
)

print("MOUNT_TYPE:", match.get("Type", "unknown"))
print("MOUNT_DESTINATION:", match.get("Destination", "unknown"))
print("MOUNT_SOURCE:", match.get("Source", "unknown"))
print("MOUNT_RW:", match.get("RW", "unknown"))

if match.get("RW") is not True:
    print("NOT_WRITABLE: Docker web mount is read-only.")
    raise SystemExit(3)

if match.get("Type") not in ("bind", "volume"):
    print("NOT_PERSISTENT: Docker web mount must be a bind mount or volume.")
    raise SystemExit(4)

print("PERSISTENT_MOUNT_DETECTED")
NOVA_DOCKER_PERSISTENCE
}

get_jellyfin_web_dir() {
    # Docker requires container-aware installation, not host filesystem paths.
    if [[ -z "${NOVA_WEB_DIR:-}" ]]; then
        local install_method
        install_method="$(detect_nova_install_method)"

        if [[ "$install_method" == "docker" ]]; then
            warn "Jellyfin Docker installation detected." >&2
            warn "Docker package installation requires container-aware handling." >&2
            return 1
        fi
    fi

    # Explicit web directory for custom Linux, macOS and container setups.
    if [[ -n "${NOVA_WEB_DIR:-}" ]]; then
        if [[ ! -d "$NOVA_WEB_DIR" || ! -f "$NOVA_WEB_DIR/index.html" ]]; then
            warn "Invalid NOVA_WEB_DIR: $NOVA_WEB_DIR" >&2
            return 1
        fi
        printf '%s\n' "$NOVA_WEB_DIR"
        return 0
    fi

    local candidates=(
        # Linux; native packages
        "/usr/share/jellyfin/web"
        "/usr/lib/jellyfin/web"
        "/var/lib/jellyfin/web"
        "/opt/jellyfin/web"
        # macOS; Homebrew (intel and apple Silicon)
        "/usr/local/share/jellyfin/web"
        "/opt/homebrew/share/jellyfin/web"
        "/opt/homebrew/opt/jellyfin/web"
        "/usr/local/opt/jellyfin/web"
        # macOS; app bundle
        "/Applications/Jellyfin.app/Contents/Resources/jellyfin-web"
        "$HOME/Applications/Jellyfin.app/Contents/Resources/jellyfin-web"
        "/Applications/Jellyfin.app/Contents/Resources/web"
        "$HOME/Applications/Jellyfin.app/Contents/Resources/web"
        # Docker; jellyfin/jellfin (official image)
        "/jellyfin/jellyfin-web" # Note: this is the path inside the container, not on the host
    )

    for p in "${candidates[@]}"; do
        if [[ -d "$p" ]]; then
            echo "$p"
            return
        fi
    done

    # This function's stdout is captured by the caller ($(get_jellyfin_web_dir)),
    # so all user-facing prompts must go to stderr or they get swallowed into
    # the return value.
    warn "Could not auto-detect Jellyfin web directory." >&2
    echo -e "${yellow}  Enter the full path to your jellyfin-web folder:${reset}" >&2
    if [[ "$OS" == "Darwin" ]]; then
        info "Example: /opt/homebrew/share/jellyfin/web" >&2
    else
        info "Example: /usr/share/jellyfin/web" >&2
        info "/Applications/Jellyfin.app/Contents/Resources/jellyfin-web" >&2
    fi
    read -rp "  Path: " path
    if [[ ! -d "$path" ]]; then
        exit_error "Directory not found: $path"
    fi
    echo "$path"
}

# ------------------------------------------------------------------------------
# Download files
# ------------------------------------------------------------------------------

download_file() {
    local repo_path="$1"
    local dest_path="$2"
    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    mkdir -p "$dest_dir"

    local url="${RAW}/${repo_path}"
    if curl -fsSL "$url" -o "$dest_path"; then
        ok "Downloaded: $(basename "$dest_path")"
    else
        exit_error "Failed to download ${repo_path} - check your internet connection."
    fi
}

install_nova_package() {
    local archive="$1"
    local web_dir="$2"
    local nova_dir="${web_dir}/nova"

    [[ -f "$archive" ]] || return 1
    [[ -d "$web_dir" ]] || return 1

    python3 - "$archive" "$nova_dir" <<'PYTHON_NOVA_PACKAGE'
import pathlib
import shutil
import sys
import tarfile
import tempfile

archive_path = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
parent = target.parent

if target.is_symlink():
    raise SystemExit("Refusing Nova target symlink")
if target.exists() and not target.is_dir():
    raise SystemExit("Nova target is not a directory")

with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    files = []
    names = set()

    for member in members:
        name = member.name.removeprefix("./")

        if name in ("", "."):
            if not member.isdir():
                raise SystemExit("Invalid Nova package root")
            continue

        path = pathlib.PurePosixPath(name)

        if (
            path.is_absolute()
            or ".." in path.parts
            or not (member.isfile() or member.isdir())
        ):
            raise SystemExit("Unsafe Nova package entry")

        if member.isfile():
            if name in names:
                raise SystemExit("Duplicate Nova package entry")
            names.add(name)
            files.append((member, path))

    required = {
        "nova.css",
        "spotlight/spotlight-loader.js",
        "spotlight/spotlight.html",
        "spotlight/spotlight.css",
        "plugins/nova-je.css",
        "plugins/nova-lite.css",
        "plugins/nova-mbe.css",
    }

    fonts = [
        name for name in names
        if name.startswith("fonts/") and name.endswith(".woff2")
    ]

    if len(files) != 30 or len(fonts) != 23 or not required.issubset(names):
        raise SystemExit("Incomplete Nova package")

    with tempfile.TemporaryDirectory(
        prefix=".nova-stage-",
        dir=parent,
    ) as temporary:
        staging = pathlib.Path(temporary) / "nova"
        staging.mkdir()

        for member, relative in files:
            destination = staging.joinpath(*relative.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)

            with archive.extractfile(member) as source:
                if source is None:
                    raise SystemExit("Unreadable Nova package entry")

                with destination.open("xb") as output:
                    shutil.copyfileobj(source, output)

        if target.is_symlink():
            raise SystemExit("Refusing Nova target symlink")

        if target.exists():
            for existing in target.rglob("*"):
                relative = existing.relative_to(target)
                destination = staging / relative
                if existing.is_symlink():
                    raise SystemExit("Refusing symlink in existing Nova directory")
                if existing.is_file() and not destination.exists():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(existing, destination)

            previous = pathlib.Path(temporary) / "previous"
            target.rename(previous)
            try:
                staging.rename(target)
            except BaseException:
                previous.rename(target)
                raise
        else:
            staging.rename(target)

print("OK: Nova package installed into", target)
PYTHON_NOVA_PACKAGE
}



transform_branding_json() {
    local mode="$1"
    python3 -c '
import json, re, sys

mode = sys.argv[1]
if mode not in ("install", "uninstall"):
    raise SystemExit("Unsupported Nova CSS operation")

data = json.load(sys.stdin)
css = data.get("CustomCss") or ""

start = "/* NOVA THEME START */"
end = "/* NOVA THEME END */"

pattern = re.escape(start) + r".*?" + re.escape(end) + r"(?:\r?\n)?"
css = re.sub(pattern, "", css, flags=re.S)

if mode == "install":
    block = (
        start
        + "\n@import url(\x27/web/nova/nova.css\x27);"
        + "\n"
        + end
    )
    css = block + ("\n" if css else "") + css

data["CustomCss"] = css
print(json.dumps(data))
' "$mode"
}



set_spotlight_index() {
    local index_file="$1"
    local mode="$2"
    if [[ ! -f "$index_file" ]]; then
        [[ "$mode" == "uninstall" ]] && return
        exit_error "Missing Jellyfin index: ${index_file}"
    fi
    python3 -c '
import os, re, shutil, sys, tempfile

path, action = sys.argv[1:]
metadata = os.stat(path)
with open(path, "r", encoding="utf-8") as handle:
    html = handle.read()
html = re.sub(r"<script[^>]*\bdata-nova-spotlight\b[^>]*></script>", "", html, flags=re.I)
if action == "install":
    tag = "<script src=\"nova/spotlight/spotlight-loader.js\" data-nova-spotlight></script>"
    if "</body>" not in html.lower():
        raise SystemExit("index.html has no closing body tag")
    html = re.sub(r"</body>", tag + "</body>", html, count=1, flags=re.I)
fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".nova-index-", text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(html)
    shutil.copystat(path, temp_path)
    try:
        os.chown(temp_path, metadata.st_uid, metadata.st_gid)
    except PermissionError:
        pass
    os.replace(temp_path, path)
except BaseException:
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    raise
' "$index_file" "$mode"
}

# ------------------------------------------------------------------------------
# Authenticate
# ------------------------------------------------------------------------------

# Globals set by connect_jellyfin (avoids subshell/TTY issue)
NOVA_TOKEN=""
NOVA_USER_NAME=""
NOVA_USER_ID=""

connect_jellyfin() {
    local server_url="$1"
    local max_tries=3
    local _response=""

    local auth_header='MediaBrowser Client="Nova Setup", Device="Setup", DeviceId="nova-setup", Version="1.0"'

    for ((try=1; try<=max_tries; try++)); do
        echo -e "${yellow}  Jellyfin admin credentials${reset}"
        echo -n "  Username: "
        read -r _username
        echo -n "  Password: "
        read -rs _password
        echo ""

        # Pass credentials via stdin to avoid exposure in process listings (ps/proc)
        local body
        body=$(printf '%s\n%s' "$_username" "$_password" | python3 -c "
import json, sys
lines = sys.stdin.read().split('\n', 1)
u, p = lines[0], lines[1] if len(lines) > 1 else ''
print(json.dumps({'Username': u, 'Pw': p}))
")

        _response=$(curl -fsSL \
            -X POST "${server_url}/Users/AuthenticateByName" \
            -H "Content-Type: application/json" \
            -H "Authorization: ${auth_header}" \
            -d "$body" 2>/dev/null) && break || true

        if ((try == max_tries)); then
            exit_error "Authentication failed after ${max_tries} attempts."
        fi

        echo ""
        fail "Invalid credentials. Attempt ${try} of ${max_tries}"
        echo ""
    done

    # Write to globals - cannot use subshell return as it breaks interactive read
    NOVA_TOKEN=$(    echo "$_response" | python3 -c "import json,sys; print(json.load(sys.stdin)['AccessToken'])")
    NOVA_USER_NAME=$(echo "$_response" | python3 -c "import json,sys; print(json.load(sys.stdin)['User']['Name'])")
    NOVA_USER_ID=$(  echo "$_response" | python3 -c "import json,sys; print(json.load(sys.stdin)['User']['Id'])")
}

get_api_header() {
    local token="$1"
    echo "MediaBrowser Client=\"Jellyfin Nova\", Device=\"Setup\", DeviceId=\"nova-setup\", Version=\"1.0\", Token=\"${token}\""
}

# ------------------------------------------------------------------------------
# Restart Jellyfin
# ------------------------------------------------------------------------------

restart_jellyfin() {
    local server_url="$1"
    local api_header="$2"

    step "Restarting Jellyfin..."

    # Try API restart first (works for all install methods)
    if curl -fsSL \
        -X POST "${server_url}/System/Restart" \
        -H "Authorization: ${api_header}" >/dev/null 2>&1; then
        ok "Restart triggered via API. Wait a few seconds then refresh."
        return
    fi

    # macOS; try Homebrew services
    if [[ "$OS" == "Darwin" ]]; then
        if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q jellyfin; then
            brew services restart jellyfin \
                && ok "Jellyfin restarted via Homebrew." \
                || warn "Could not restart via Homebrew. Restart Jellyfin manually."
            return
        fi
    fi

    # Linux; try systemctl
    if command -v systemctl &>/dev/null && systemctl list-units --type=service 2>/dev/null | grep -q jellyfin; then
        sudo systemctl restart jellyfin \
            && ok "Jellyfin service restarted." \
            || warn "Could not restart via systemctl. Restart Jellyfin manually."
        return
    fi

    warn "Could not restart automatically. Please restart Jellyfin manually."
}

# ------------------------------------------------------------------------------
# Install
# ------------------------------------------------------------------------------

install_nova() {
    show_header "Installer"

    # Server URL
    echo -e "${yellow}  Jellyfin server URL${reset}"
    echo -e "${gray}  Press ENTER to use default (http://localhost:8096)${reset}"
    read -rp "  URL: " input_url
    local server_url="${input_url:-http://localhost:8096}"
    server_url="${server_url%/}"
    ok "Server: ${server_url}"
    echo ""

    # Authenticate
    step "Authenticating..."
    echo ""
    connect_jellyfin "$server_url"
    local token="$NOVA_TOKEN"
    local user_name="$NOVA_USER_NAME"
    local user_id="$NOVA_USER_ID"

    local api_header
    api_header=$(get_api_header "$token")

    echo ""
    ok "Authenticated as: ${user_name}"
    echo ""

    # Resolve native or Docker installation target.
    step "Locating Jellyfin installation..."
    local web_dir=""
    local nova_install_method
    local nova_docker_container=""

    nova_install_method="$(detect_nova_install_method)"

    if [[ "$nova_install_method" == "docker" ]]; then
        resolve_nova_docker_target || exit_error "Could not resolve Jellyfin Docker target."
        nova_docker_container="$NOVA_DOCKER_CONTAINER"
        web_dir="$NOVA_DOCKER_WEB_DIR"

        local nova_docker_family
        nova_docker_family="$(get_nova_docker_image_family "$nova_docker_container")" \
            || exit_error "Could not identify Jellyfin Docker image."

        case "$nova_docker_family" in
            linuxserver)
                step "Checking persistent Docker configuration..."
                check_nova_docker_config_persistence "$nova_docker_container" \
                    || exit_error "Persistent Docker /config mount required."

                step "Checking persistent LinuxServer startup hook..."
                check_nova_docker_init_persistence "$nova_docker_container" \
                    || exit_error "Persistent /custom-cont-init.d mount required."
                ;;
            official)
                exit_error "Official Jellyfin Docker persistence is not implemented yet."
                ;;
            *)
                exit_error "Unsupported Jellyfin Docker image: persistent installation unavailable."
                ;;
        esac
    else
        web_dir="$(get_jellyfin_web_dir)" || exit_error "Could not locate Jellyfin web directory."
    fi

    local spotlight_dir="${web_dir}/nova/spotlight"

    # Install Nova CSS, fonts, plugins and Spotlight from the package.
    local installer_dir
    installer_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    local nova_package="${NOVA_PACKAGE:-${installer_dir}/jellyfin-nova-package.tar.gz}"

    if [[ ! -f "$nova_package" ]]; then
        if [[ -n "${NOVA_PACKAGE:-}" ]]; then
            exit_error "Explicit Nova package not found: ${nova_package}"
        fi

        step "Downloading Nova package..."
        nova_package="$(mktemp "${TMPDIR:-/tmp}/jellyfin-nova-package.XXXXXXXX.tar.gz")"
        trap "rm -f -- $(printf '%q' "$nova_package")" EXIT
        if ! curl -fsSL "${RAW}/scripts/installer/jellyfin-nova-package.tar.gz" -o "$nova_package"; then
            rm -f -- "$nova_package"
            exit_error "Failed to download Nova package."
        fi
    fi

    step "Installing Nova package..."

    if [[ "$nova_install_method" == "docker" ]]; then
        step "Validating Nova package before Docker changes..."
        if ! validate_nova_package_before_docker "$nova_package"; then
            exit_error "Nova package validation failed; Docker unchanged."
        fi

        step "Installing persistent Nova startup hook..."
        if ! install_nova_docker_init_hook "$nova_docker_container" "$installer_dir"; then
            exit_error "Could not install persistent Nova startup hook."
        fi

        if ! install_nova_docker_package "$nova_docker_container" "$nova_package" "$web_dir"; then
            exit_error "Nova Docker package installation failed."
        fi
    else
        if ! install_nova_package "$nova_package" "$web_dir"; then
            exit_error "Nova package installation failed."
        fi
    fi

    ok "Nova CSS, fonts, plugins and Spotlight installed."
    echo ""

    local index_file="${web_dir}/index.html"

    if [[ "$nova_install_method" == "docker" ]]; then
        step "Integrating Nova Spotlight in Jellyfin Docker..."
        if ! set_nova_docker_spotlight_index "$nova_docker_container" "$web_dir" install; then
            exit_error "Could not integrate Nova Spotlight in Docker index.html."
        fi
    else
        [[ -f "$index_file" ]] || exit_error "Missing Jellyfin index: ${index_file}"
        [[ -w "$index_file" ]] || exit_error "Jellyfin index is not writable: ${index_file}"
        python3 -c 'import sys; raise SystemExit(0 if "</body>" in open(sys.argv[1], encoding="utf-8").read().lower() else 1)' "$index_file" \
            || exit_error "Jellyfin index.html has no closing body tag."
    fi

    # Apply CSS
    step "Applying Nova CSS..."
    local branding
    if ! branding=$(curl -fsSL \
        -X GET "${server_url}/Branding/Configuration" \
        -H "Authorization: ${api_header}"); then
        exit_error "Could not fetch Jellyfin branding configuration. Nova CSS was not activated."
    fi

    [[ -n "$branding" ]] || exit_error "Empty Jellyfin branding configuration."

    local updated_branding
    if ! updated_branding=$(printf '%s' "$branding" | transform_branding_json install); then
        exit_error "Could not prepare Nova CSS configuration."
    fi

    if ! curl -fsSL \
        -X POST "${server_url}/System/Configuration/Branding" \
        -H "Content-Type: application/json" \
        -H "Authorization: ${api_header}" \
        -d "$updated_branding" >/dev/null; then
        exit_error "Jellyfin rejected the Nova CSS configuration."
    fi

    ok "Nova CSS applied."
    echo ""

    # Configure display prefs
    step "Configuring theme settings..."
    local display_prefs
    display_prefs=$(curl -fsSL \
        -X GET "${server_url}/DisplayPreferences/usersettings?userId=${user_id}&client=emby" \
        -H "Authorization: ${api_header}" 2>/dev/null) || true

    if [[ -n "$display_prefs" ]]; then
        # Ask before reordering home sections
        echo ""
        echo -e "${yellow}  Reorder home screen sections?${reset}"
        info "Recommended order: Continue Watching, Next Up, My Media, Recently Added."
        info "(Recommended for best experience with Nova)"
        read -rp "  Reorder sections? [Y/n]: " reorder_choice
        echo ""
        # [Y/n] convention: ENTER (empty) defaults to Yes
        [[ -z "${reorder_choice// }" ]] && reorder_choice="Y"

        local reorder_sections=false
        case "$reorder_choice" in
            [Yy]) reorder_sections=true ;;
        esac

        local updated_prefs
        if [[ "$reorder_sections" == true ]]; then
            updated_prefs=$(echo "$display_prefs" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d.setdefault('CustomPrefs', {})
p['appTheme']       = 'dark'
p['dashboardTheme'] = 'dark'
p['homesection0']   = 'resume'
p['homesection1']   = 'nextup'
p['homesection2']   = 'smalllibrarytiles'
p['homesection3']   = 'latestmedia'
for i in range(4, 10):
    p[f'homesection{i}'] = 'none'
print(json.dumps(d))
")
        else
            updated_prefs=$(echo "$display_prefs" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d.setdefault('CustomPrefs', {})
p['appTheme']       = 'dark'
p['dashboardTheme'] = 'dark'
print(json.dumps(d))
")
        fi

        curl -fsSL \
            -X POST "${server_url}/DisplayPreferences/usersettings?userId=${user_id}&client=emby" \
            -H "Content-Type: application/json" \
            -H "Authorization: ${api_header}" \
            -d "$updated_prefs" >/dev/null 2>&1 \
            && ok "Client and dashboard themes set to Dark." \
            && { [[ "$reorder_sections" == true ]] && ok "Home screen sections configured." || skip "Home screen sections left unchanged."; } \
            || warn "Could not configure theme settings. Set manually in Settings > Display."
    else
        warn "Could not fetch display preferences."
    fi
    echo ""

    # Install Nova Spotlight
    step "Installing Nova Spotlight add-on..."
    echo ""

    if [[ "$nova_install_method" == "docker" ]]; then
        ok "Nova Spotlight loader already integrated in Docker."
    else
        for f in "spotlight.html" "spotlight.css" "spotlight-loader.js"; do
            [[ -f "${spotlight_dir}/${f}" ]] || exit_error "Missing Nova Spotlight file: ${f}"
        done

        set_spotlight_index "$index_file" install
        ok "Nova Spotlight loader installed."
    fi
    echo ""

    # Restart
    restart_jellyfin "$server_url" "$api_header"

    # Done
    echo ""
    echo -e "${cyan}  ================================================${reset}"
    echo -e "${green}  Installation complete!${reset}"
    echo -e "${cyan}  ================================================${reset}"
    echo ""
    echo "  Next steps:"
    echo -e "${red}    1. Delete browser cache${reset}"
    echo -e "${yellow}    2. Hard refresh your browser (Ctrl+F5)${reset}"
    echo -e "${gray}    3. Relaunch Jellyfin Media Player if using the desktop app${reset}"
    echo ""
    echo -e "${green}  Dark theme configured for the client and dashboard.${reset}"
    info "Nova requires the Dark base theme to display correctly."
    echo ""
    echo -e "${green}  Tip: Turn on 'Show Backdrops' in display settings for best experience.${reset}"
    echo ""
    read -rp "  Press Enter to exit: "
}

# ------------------------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------------------------

uninstall_nova() {
    show_header "Uninstaller"

    echo -e "${yellow}  Jellyfin server URL${reset}"
    echo -e "${gray}  Press ENTER to use default (http://localhost:8096)${reset}"
    read -rp "  URL: " input_url
    local server_url="${input_url:-http://localhost:8096}"
    server_url="${server_url%/}"
    ok "Server: ${server_url}"
    echo ""

    step "Authenticating..."
    echo ""
    connect_jellyfin "$server_url"
    local token="$NOVA_TOKEN"

    local api_header
    api_header=$(get_api_header "$token")

    echo ""

    # Resolve native or Docker uninstall target.
    step "Locating Jellyfin installation..."
    local web_dir=""
    local nova_install_method
    local nova_docker_container=""

    nova_install_method="$(detect_nova_install_method)"

    if [[ "$nova_install_method" == "docker" ]]; then
        resolve_nova_docker_target || exit_error "Could not resolve Jellyfin Docker target."
        nova_docker_container="$NOVA_DOCKER_CONTAINER"
        web_dir="$NOVA_DOCKER_WEB_DIR"
    else
        web_dir="$(get_jellyfin_web_dir)" || exit_error "Could not locate Jellyfin web directory."
    fi

    ok "Found: ${web_dir}"
    echo ""

    # Validate the package manifest before changing Jellyfin.
    local installer_dir
    installer_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    local nova_package="${NOVA_PACKAGE:-${installer_dir}/jellyfin-nova-package.tar.gz}"

    if [[ ! -f "$nova_package" ]]; then
        if [[ -n "${NOVA_PACKAGE:-}" ]]; then
            exit_error "Explicit Nova package not found: ${nova_package}"
        fi

        step "Downloading Nova package..."
        nova_package="$(mktemp "${TMPDIR:-/tmp}/jellyfin-nova-package.XXXXXXXX.tar.gz")"
        trap "rm -f -- $(printf '%q' "$nova_package")" EXIT

        if ! curl -fsSL "${RAW}/scripts/installer/jellyfin-nova-package.tar.gz" -o "$nova_package"; then
            exit_error "Failed to download Nova package."
        fi
    fi

    python3 - "$nova_package" <<'NOVA_PREFLIGHT' || exit_error "Invalid Nova package archive."
import pathlib, sys, tarfile

archive = pathlib.Path(sys.argv[1])
with tarfile.open(archive, "r:gz") as tar:
    members = tar.getmembers()
    files = [m for m in members if m.isfile()]
    names = [m.name.removeprefix("./") for m in files]
    if len(names) != 30 or len(set(names)) != 30:
        raise SystemExit("Unexpected Nova package manifest")
    if any(
        pathlib.PurePosixPath(name).is_absolute()
        or ".." in pathlib.PurePosixPath(name).parts
        for name in names
    ):
        raise SystemExit("Unsafe Nova package path")
    if any(not (m.isfile() or m.isdir()) for m in members):
        raise SystemExit("Unsupported Nova package member")
NOVA_PREFLIGHT

    # Remove Nova CSS
    step "Removing Nova CSS..."
    local branding
    if ! branding=$(curl -fsSL \
        -X GET "${server_url}/Branding/Configuration" \
        -H "Authorization: ${api_header}"); then
        exit_error "Could not fetch branding configuration. Uninstall stopped."
    fi

    [[ -n "$branding" ]] || exit_error "Empty branding configuration. Uninstall stopped."

    local updated_branding
    if ! updated_branding=$(printf '%s' "$branding" | transform_branding_json uninstall); then
        exit_error "Could not prepare Nova CSS removal."
    fi

    if ! curl -fsSL \
        -X POST "${server_url}/System/Configuration/Branding" \
        -H "Content-Type: application/json" \
        -H "Authorization: ${api_header}" \
        -d "$updated_branding" >/dev/null; then
        exit_error "Jellyfin rejected Nova CSS removal. Uninstall stopped."
    fi

    ok "Nova CSS removed."
    echo ""

    step "Removing Spotlight loader..."

    if [[ "$nova_install_method" == "docker" ]]; then
        local nova_docker_family
        nova_docker_family="$(get_nova_docker_image_family "$nova_docker_container")" \
            || exit_error "Could not identify Jellyfin Docker image."

        if [[ "$nova_docker_family" == "linuxserver" ]]; then
            step "Removing persistent Nova startup hook..."
            if ! remove_nova_docker_init_hook "$nova_docker_container"; then
                exit_error "Could not remove Nova startup hook. Uninstall stopped."
            fi
        fi

        if ! set_nova_docker_spotlight_index "$nova_docker_container" "$web_dir" uninstall; then
            exit_error "Could not remove Nova Spotlight from Docker index.html."
        fi
    else
        set_spotlight_index "${web_dir}/index.html" uninstall
    fi

    ok "Spotlight loader removed."
    echo ""

    # Remove only known Nova package files.
    step "Removing Nova package files..."

    if [[ "$nova_install_method" == "docker" ]]; then
        if ! remove_nova_docker_package "$nova_docker_container" "$nova_package" "$web_dir"; then
            exit_error "Nova Docker package cleanup failed."
        fi

        if [[ "$nova_docker_family" == "linuxserver" ]]; then
            step "Removing persistent Nova package files..."
            if ! remove_nova_docker_persistent_package "$nova_docker_container" "$nova_package"; then
                exit_error "Persistent Nova package cleanup failed."
            fi
        fi
    else
        python3 - "$nova_package" "$web_dir" <<'NOVA_CLEANUP' || exit_error "Nova package cleanup failed."
import pathlib, sys, tarfile

archive = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2]) / "nova"

if root.is_symlink():
    raise SystemExit("Refusing Nova symlink")

if root.is_dir():
    with tarfile.open(archive, "r:gz") as tar:
        names = [m.name for m in tar if m.isfile()]
    if len(names) != 30 or len(set(names)) != 30:
        raise SystemExit("Unexpected package manifest")
    paths = []
    for name in names:
        rel = pathlib.PurePosixPath(name)
        if rel.is_absolute() or ".." in rel.parts:
            raise SystemExit("Unsafe package path")
        path = root.joinpath(*rel.parts)
        if any(parent.is_symlink() for parent in path.parents if parent != root):
            raise SystemExit("Unsafe symlink parent")
        paths.append(path)
    for path in paths:
        if path.is_file() or path.is_symlink():
            path.unlink()
    for directory in sorted(
        {parent for path in paths for parent in path.parents if parent == root or root in parent.parents},
        key=lambda x: len(x.parts), reverse=True
    ):
        if directory.is_dir() and not directory.is_symlink():
            try:
                directory.rmdir()
            except OSError:
                pass
NOVA_CLEANUP
    fi

    echo ""
    # Restart
    restart_jellyfin "$server_url" "$api_header"

    echo ""
    echo -e "${cyan}  ================================================${reset}"
    echo -e "${green}  Uninstall complete!${reset}"
    echo -e "${cyan}  ================================================${reset}"
    echo ""
    echo "  Next steps:"
    echo -e "${red}    1. Delete browser cache${reset}"
    echo -e "${yellow}    2. Hard refresh your browser (Ctrl+F5)${reset}"
    echo -e "${gray}    3. Relaunch Jellyfin Media Player if using the desktop app${reset}"
    echo ""
    read -rp "  Press Enter to exit: "
}

# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------

main() {
    if [[ "$EUID" -ne 0 ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            warn "Not running as root. Some file operations may require sudo."
            info "If you encounter permission errors, re-run with: sudo bash scripts/installer/nova-installer.sh"
            echo ""
        else
            echo -e "${red}  This script must be run as root (sudo).${reset}"
            exit 1
        fi
    fi

    check_dependencies

    show_header "Setup"

    echo "  What would you like to do?"
    echo ""
    echo -e "${green}   [1] Install${reset}        ${yellow}[2] Uninstall${reset}"
    echo ""
    read -rp "  Enter 1 or 2: " choice

    case "$choice" in
        1) install_nova ;;
        2) uninstall_nova ;;
        *) exit_error "Invalid choice. Please enter 1 or 2." ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
