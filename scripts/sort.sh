#!/bin/bash

set -euo pipefail

# Function to sort packages in a file
sort_packages() {
    local file_path="$1"
    
    # Get absolute path
    file_path=$(realpath "$file_path")
    
    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        echo "Error: File '$file_path' not found." >&2
        return 1
    fi
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Ensure cleanup of temp file
    trap "rm -f '$temp_file'" EXIT
    
    # Read file, remove empty lines and whitespace, sort uniquely
    if ! grep -v '^[[:space:]]*$' "$file_path" | \
         sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
         sort -u > "$temp_file"; then
        echo "An error occurred while processing the file." >&2
        return 1
    fi
    
    # Replace original file with sorted content
    if ! mv "$temp_file" "$file_path"; then
        echo "An error occurred while writing to the file." >&2
        return 1
    fi
    
    echo "File '$file_path' formatted and duplicates removed successfully."
    return 0
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [FILE_PATH]

Formats the content of a package list file alphabetically and removes duplicates.

Arguments:
    FILE_PATH    Path to the package list file (default: ../archiso/packages.x86_64)

Options:
    -h, --help   Show this help message

EOF
}

# Main function
main() {
    local file_path="../archiso/packages.x86_64"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
            *)
                file_path="$1"
                shift
                ;;
        esac
    done
    
    # Sort packages
    sort_packages "$file_path"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi