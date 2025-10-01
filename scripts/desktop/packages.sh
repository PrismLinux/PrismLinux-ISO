#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# PrismLinux Package Preparation Script
# Downloads driver packages and distributes them to their respective directories.

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly LOG_PREFIX="[$SCRIPT_NAME]"
# Set the cache directory for downloaded packages
readonly PKGCACHE_DIR="/var/cache/pacman/pkg-prismlinux-build"

# Driver definitions: "vendor/subdirectory/packages..."
declare -Ar DRIVERS=(
    # ["nvidia-open"]="nvidia/open/nvidia-open nvidia-open-dkms nvidia-utils"
    # ["nvidia-470"]="nvidia/legacy-470/nvidia-470xx-dkms nvidia-470xx-utils"
    # ["nvidia-390"]="nvidia/legacy-390/nvidia-390xx-dkms nvidia-390xx-utils"
    # ["nvidia-340"]="nvidia/legacy-340/nvidia-340xx-dkms nvidia-340xx-utils"
    # ["nouveau"]="nvidia/nouveau/xf86-video-nouveau"
    ["intel-legacy"]="intel/legacy/xf86-video-intel"
)

log() { echo "$LOG_PREFIX $*" >&2; }
log_error() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

trap 'log_error "Failed at line $LINENO: $BASH_COMMAND"' ERR

# Finds the project root by searching upwards for `iso-build.yml`
find_project_root() {
    local dir
    dir="$(dirname "$(realpath "$0")")"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/iso-build.yml" ]]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    log_error "Could not find the project root (missing iso-build.yml)."
}

# Collects unique package names from the DRIVERS array
collect_unique_packages() {
    local -A unique_pkgs
    for config in "${DRIVERS[@]}"; do
        IFS='/' read -r _ _ packages <<< "$config"
        for pkg in $packages; do
            unique_pkgs["$pkg"]=1
        done
    done
    printf '%s\n' "${!unique_pkgs[@]}"
}

# Downloads all required packages, ensuring they exist in the custom cache.
download_packages() {
    log "Preparing package cache..."
    sudo mkdir -p "$PKGCACHE_DIR"
    sudo chown "$USER" "$PKGCACHE_DIR"

    local packages_to_download=()
    local all_packages
    readarray -t all_packages < <(collect_unique_packages)

    log "Checking for ${#all_packages[@]} unique packages in the build cache..."
    for pkg_name in "${all_packages[@]}"; do
        # Check if a version of the package already exists in our custom build cache.
        # We use a glob with `ls` to see if any version of the package file is present.
        if ls "$PKGCACHE_DIR/$pkg_name"-*.pkg.tar.zst >/dev/null 2>&1; then
            log "  -> Found '$pkg_name' in build cache. Skipping."
        else
            log "  -> Marking '$pkg_name' for download."
            packages_to_download+=("$pkg_name")
        fi
    done

    if [[ ${#packages_to_download[@]} -gt 0 ]]; then
        log "Downloading ${#packages_to_download[@]} missing packages..."
        sudo pacman -Sw --noconfirm --cachedir "$PKGCACHE_DIR" "${packages_to_download[@]}"
    else
        log "All required packages are already in the build cache."
    fi

    log "Package cache preparation complete."
}

# Distributes packages to their respective directories
distribute_packages() {
    local target_base_dir="$1"
    log "Distributing packages..."

    for driver in "${!DRIVERS[@]}"; do
        local config="${DRIVERS[$driver]}"
        IFS='/' read -r vendor subdir packages <<< "$config"
        local target_dir="$target_base_dir/$vendor/$subdir"
        mkdir -p "$target_dir"

        log "  -> Processing $driver into $target_dir"
        for pkg_name in $packages; do
            # Find the package file in our custom cache (handling version variations)
            local pkg_file
            pkg_file=$(find "$PKGCACHE_DIR" -name "$pkg_name-*.pkg.tar.zst" -print -quit)

            if [[ -f "$pkg_file" ]]; then
                cp "$pkg_file" "$target_dir/"
            else
                log_error "Package file for '$pkg_name' not found in cache: $PKGCACHE_DIR"
            fi
        done
    done
    log "Package distribution complete."
}

main() {
    local project_root
    project_root=$(find_project_root)
    log "Project root found at: $project_root"

    local target_opt_dir="$project_root/build/desktop/profile/airootfs/opt"
    if [[ ! -d "$(dirname "$target_opt_dir")" ]]; then
        log_error "Base directory not found: $(dirname "$target_opt_dir")"
    fi

    mkdir -p "$target_opt_dir"

    download_packages
    distribute_packages "$target_opt_dir"

    log "All packages have been successfully downloaded and distributed."
}

main "$@"
