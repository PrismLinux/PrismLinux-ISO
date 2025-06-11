#!/bin/bash

set -euo pipefail

# Global variables
PRIV_CMD=""
WORK_DIR=""
OUTPUT_DIR=""
PROJECT_ROOT=""
ARCHISO_SOURCE_DIR=""
WORK_ARCHISO_DIR=""
CLEAN_FIRST=false

# Function to determine privilege escalation command
get_privilege_command() {
    if [[ $EUID -eq 0 ]]; then
        echo "Script is running as root. Privilege escalation tool is not needed."
        PRIV_CMD=""
        return 0
    fi

    if command -v doas >/dev/null 2>&1; then
        echo "Using 'doas' for privilege escalation."
        PRIV_CMD="doas"
        return 0
    elif command -v sudo >/dev/null 2>&1; then
        echo "Using 'sudo' for privilege escalation."
        PRIV_CMD="sudo"
        return 0
    fi

    echo "Error: Not running as root, and neither 'doas' nor 'sudo' found in PATH." >&2
    exit 1
}

# Function to generate ISO filename (kept for compatibility)
generate_iso_filename() {
    local build_date=$(date +%Y%m%d)
    local arch="x86_64"
    echo "CrystalLinux-${build_date}-${arch}.iso"
}

# Function to update version file
update_version_file() {
    local airootfs_path="$1"
    local version_file="${airootfs_path}/etc/crystallinux-version"
    local build_date=$(date +%Y.%m)
    
    if ! echo "$build_date" > "$version_file"; then
        echo "Error writing to version file $version_file" >&2
        return 1
    fi
    
    echo "Updated version file: $version_file with date $build_date"
}

# Function to generate SHA256 checksum
generate_checksum() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        echo "Error: File $file_path not found for checksum generation" >&2
        return 1
    fi
    
    sha256sum "$file_path" | cut -d' ' -f1
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Crystal Linux ISO.

OPTIONS:
    --work-dir DIR      Working directory for the build (default: ../build/work)
    --output-dir DIR    Output directory for the ISO (default: ../build/out)
    -c, --clean         Clean the work directory before building
    -h, --help          Show this help message

EOF
}

# Function to parse command line arguments
parse_args() {
    WORK_DIR="../build/work"
    OUTPUT_DIR="../build/out"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --work-dir)
                WORK_DIR="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--clean)
                CLEAN_FIRST=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to setup and verify paths
setup_paths() {
    WORK_DIR=$(realpath "$WORK_DIR")
    OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
    
    local script_dir=$(dirname "$(realpath "$0")")
    local iso_dir=$(dirname "$script_dir")
    PROJECT_ROOT=$(dirname "$iso_dir")
    ARCHISO_SOURCE_DIR="${iso_dir}/archiso"
    WORK_ARCHISO_DIR="${WORK_DIR}/archiso"
    
    # Create necessary directories
    mkdir -p "$(dirname "$WORK_DIR")" "$WORK_DIR" "$OUTPUT_DIR"
    
    if [[ ! -d "$ARCHISO_SOURCE_DIR" ]]; then
        echo "Error: Archiso source directory not found at $ARCHISO_SOURCE_DIR" >&2
        return 1
    fi
    
    return 0
}

# Function to clean work directory
clean_work_dir() {
    if [[ "$CLEAN_FIRST" == true && -d "$WORK_DIR" ]]; then
        echo "Cleaning work directory: $WORK_DIR"
        
        if [[ -n "$PRIV_CMD" ]]; then
            if ! $PRIV_CMD rm -rf "$WORK_DIR"; then
                echo "Error cleaning work directory" >&2
                return 1
            fi
        else
            if ! rm -rf "$WORK_DIR"; then
                echo "Error cleaning work directory" >&2
                return 1
            fi
        fi
        
        mkdir -p "$WORK_DIR"
    fi
    
    return 0
}

# Function to copy archiso profile
copy_archiso_profile() {
    echo "Copying archiso profile from $ARCHISO_SOURCE_DIR to $WORK_ARCHISO_DIR"
    
    mkdir -p "$WORK_ARCHISO_DIR"
    
    # Try rsync first, fall back to cp
    if command -v rsync >/dev/null 2>&1; then
        if rsync -a --delete --exclude='.git' "${ARCHISO_SOURCE_DIR}/" "$WORK_ARCHISO_DIR"; then
            echo "Archiso profile copied using rsync."
            return 0
        else
            echo "rsync failed, falling back to cp."
        fi
    else
        echo "rsync not found, using cp."
    fi
    
    # Fallback to cp
    if [[ -d "$WORK_ARCHISO_DIR" ]]; then
        rm -rf "$WORK_ARCHISO_DIR"
    fi
    
    if ! cp -r "$ARCHISO_SOURCE_DIR" "$WORK_ARCHISO_DIR"; then
        echo "Error copying archiso directory" >&2
        return 1
    fi
    
    echo "Archiso profile copied using cp."
    return 0
}

# Function to run mkarchiso
run_mkarchiso() {
    echo "Starting ISO build in $WORK_ARCHISO_DIR"
    local original_cwd=$(pwd)
    
    cd "$PROJECT_ROOT"
    
    local mkarchiso_command=()
    if [[ -n "$PRIV_CMD" ]]; then
        mkarchiso_command+=("$PRIV_CMD")
    fi
    mkarchiso_command+=("mkarchiso" "-v" "-w" "$WORK_DIR" "-o" "$OUTPUT_DIR" "$WORK_ARCHISO_DIR")
    
    echo "Executing command: ${mkarchiso_command[*]}"
    
    if ! "${mkarchiso_command[@]}"; then
        echo "mkarchiso exited with error" >&2
        cd "$original_cwd"
        return 1
    fi
    
    cd "$original_cwd"
    return 0
}

# Function to process output ISO
process_output_iso() {
    local generated_iso_name_pattern="CrystalLinux-"
    local iso_path=""
    
    # Find the most recent ISO file
    local newest_file=""
    local newest_time=0
    
    for file in "$OUTPUT_DIR"/${generated_iso_name_pattern}*.iso; do
        if [[ -f "$file" ]]; then
            local file_time=$(stat -c %Y "$file" 2>/dev/null || echo 0)
            if [[ $file_time -gt $newest_time ]]; then
                newest_time=$file_time
                newest_file="$file"
            fi
        fi
    done
    
    if [[ -z "$newest_file" ]]; then
        echo "Error: Could not find the generated ISO file in $OUTPUT_DIR" >&2
        return 1
    fi
    
    iso_path="$newest_file"
    local iso_name=$(basename "$iso_path")
    
    echo "Found generated ISO: $iso_name"
    echo "Generating SHA256 checksum for $iso_name"
    
    local checksum
    if ! checksum=$(generate_checksum "$iso_path"); then
        echo "Failed to generate checksum." >&2
        return 1
    fi
    
    local checksum_file_path="${iso_path}.sha256"
    if ! echo "$checksum  $iso_name" > "$checksum_file_path"; then
        echo "Error saving checksum file" >&2
        return 1
    fi
    
    echo "Checksum saved to $checksum_file_path"
    echo "$iso_path"
}

# Function to handle ownership
handle_ownership() {
    local sudo_user="${SUDO_USER:-}"
    
    if [[ -z "$sudo_user" ]]; then
        echo "Not running under sudo/doas, or original user not detected. Skipping ownership change."
        return 0
    fi
    
    echo "Attempting to change ownership of $OUTPUT_DIR to user '$sudo_user'..."
    
    local chown_command=()
    if [[ -n "$PRIV_CMD" ]]; then
        chown_command+=("$PRIV_CMD")
    fi
    chown_command+=("chown" "-R" "$sudo_user" "$OUTPUT_DIR")
    
    if "${chown_command[@]}"; then
        echo "Ownership changed successfully."
        return 0
    else
        echo "Warning: Could not change ownership of $OUTPUT_DIR." >&2
        return 1
    fi
}

# Function to copy package list
copy_package_list() {
    local final_iso_path="$1"
    local package_list_source="${WORK_DIR}/iso/arch/pkglist.x86_64.txt"
    local package_list_dest
    
    if [[ -n "$final_iso_path" ]]; then
        local iso_basename=$(basename "$final_iso_path" .iso)
        package_list_dest="${OUTPUT_DIR}/${iso_basename}.pkgs.txt"
    else
        package_list_dest="${OUTPUT_DIR}/pkglist.x86_64.txt"
    fi
    
    if [[ -f "$package_list_source" ]]; then
        echo "Copying package list to $package_list_dest"
        if cp "$package_list_source" "$package_list_dest"; then
            echo "$package_list_dest"
            return 0
        else
            echo "Error copying package list" >&2
            return 1
        fi
    else
        echo "Warning: Package list file not found at $package_list_source" >&2
        return 1
    fi
}

# Main function
main_build() {
    # Initialize privilege command
    get_privilege_command
    
    # Parse arguments
    parse_args "$@"
    
    # Setup paths
    if ! setup_paths; then
        echo "Failed to set up paths. Exiting." >&2
        exit 1
    fi
    
    # Clean work directory if requested
    if ! clean_work_dir; then
        echo "Failed to clean work directory. Exiting." >&2
        exit 1
    fi
    
    # Copy archiso profile
    if ! copy_archiso_profile; then
        echo "Failed to copy archiso profile. Exiting." >&2
        exit 1
    fi
    
    # Update version file
    if ! update_version_file "${WORK_ARCHISO_DIR}/airootfs"; then
        echo "Failed to update version file. Exiting." >&2
        exit 1
    fi
    
    # Run mkarchiso
    if ! run_mkarchiso; then
        echo "mkarchiso build failed. Exiting." >&2
        exit 1
    fi
    
    # Process output ISO
    local final_iso_path
    if final_iso_path=$(process_output_iso); then
        # Handle ownership
        handle_ownership
        
        # Copy package list
        local package_list_dest
        package_list_dest=$(copy_package_list "$final_iso_path")
        
        echo
        echo "Build process completed."
        echo "Final ISO located at: $final_iso_path"
        if [[ -n "$package_list_dest" ]]; then
            echo "Package list located at: $package_list_dest"
        fi
    else
        echo
        echo "ISO output processing failed. The build may not have completed successfully." >&2
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_build "$@"
fi