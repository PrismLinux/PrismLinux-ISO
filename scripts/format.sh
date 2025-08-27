#!/bin/bash

set -euo pipefail

# Function to sort packages within sections of a file
sort_packages_by_section() {
  local file_path="$1"

  # Check if file exists
  if [[ ! -f "$file_path" ]]; then
    echo "Error: File '$file_path' not found." >&2
    exit 1
  fi

  # Create temporary file
  local temp_file
  temp_file=$(mktemp)

  # Ensure cleanup of temp file
  trap "rm -f '$temp_file'" EXIT

  # Process file using awk to preserve sections and sort packages
  awk '
    BEGIN { in_section=0; section_lines="" }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {
      if (in_section && section_lines != "") {
        # Sort and deduplicate packages in the current section
        split(section_lines, lines, "\n");
        delete seen;
        for (i in lines) {
          if (lines[i] ~ /^[[:space:]]*[a-zA-Z0-9]/) {
            trimmed = lines[i];
            sub(/^[[:space:]]+/, "", trimmed);
            sub(/[[:space:]]+$/, "", trimmed);
            if (trimmed != "" && !(trimmed in seen)) {
              seen[trimmed] = lines[i];
            }
          }
        }
        # Print sorted unique packages
        n = asorti(seen, sorted);
        for (i=1; i<=n; i++) {
          print seen[sorted[i]];
        }
        section_lines = "";
        in_section = 0;
      }
      print $0; # Print comment or empty line
      if (/^[[:space:]]*#/) { in_section=1; }
      next;
    }
    {
      if (in_section) { section_lines = section_lines $0 "\n"; }
      else { print $0; }
    }
    END {
      if (section_lines != "") {
        split(section_lines, lines, "\n");
        delete seen;
        for (i in lines) {
          if (lines[i] ~ /^[[:space:]]*[a-zA-Z0-9]/) {
            trimmed = lines[i];
            sub(/^[[:space:]]+/, "", trimmed);
            sub(/[[:space:]]+$/, "", trimmed);
            if (trimmed != "" && !(trimmed in seen)) {
              seen[trimmed] = lines[i];
            }
          }
        }
        n = asorti(seen, sorted);
        for (i=1; i<=n; i++) {
          print seen[sorted[i]];
        }
      }
    }
  ' "$file_path" > "$temp_file"

  # Replace the original file
  if ! mv "$temp_file" "$file_path"; then
    echo "Error: Failed to write to '$file_path'." >&2
    exit 1
  fi

  echo "File '$file_path' sorted by sections and duplicates removed successfully, preserving leading whitespace."
}

# Function to show usage
show_usage() {
  cat <<EOF
Usage: $0 [FILE_PATH]

Sorts the content of a package list file alphabetically within sections
defined by comments/headers and removes duplicates within those sections,
while preserving the leading whitespace (indentation) of package lines.

Arguments:
    FILE_PATH    Path to the package list file (default: profiles/desktop/packages.x86_64)

Options:
    -h, --help   Show this help message

EOF
}

# Main function
main() {
  local file_path="profiles/desktop/packages.x86_64"

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
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
  sort_packages_by_section "$file_path"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
