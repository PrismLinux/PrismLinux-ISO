#!/bin/bash

set -euo pipefail

# Function to sort packages within sections of a file
sort_packages_by_section() {
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

  local current_section_packages=()
  local output_lines=()
  local in_package_block=0 # 0 = not in package block, 1 = in package block

  # Read the file line by line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Check if the line is a comment or header (starts with any number of spaces followed by #)
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      # If we were in a package block, sort and append accumulated packages
      if [[ "$in_package_block" -eq 1 ]]; then
        local temp_sort_input=""
        for pkg_line in "${current_section_packages[@]}"; do
          # Trim leading/trailing whitespace for sorting key, but keep original line
          local trimmed_pkg=$(echo "$pkg_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          if [[ -n "$trimmed_pkg" ]]; then
            # Use a tab as a delimiter for sort/awk
            temp_sort_input+="${trimmed_pkg}\t${pkg_line}\n"
          fi
        done

        local sorted_unique_block=()
        if [[ -n "$temp_sort_input" ]]; then
          # Sort by the trimmed name (first field), then use awk to remove duplicates
          # based on the trimmed name, printing the original line (second field).
          # `sort -t$'\t' -k1,1` sorts by the first tab-delimited field.
          # `awk -F'\t' '!seen[$1]++ { print $2 }'` prints the second field for unique first fields.
          IFS=$'\n' sorted_unique_block=($(echo -e "$temp_sort_input" | sort -t$'\t' -k1,1 | awk -F'\t' '!seen[$1]++ { print $2 }'))
        fi

        output_lines+=("${sorted_unique_block[@]}")
        current_section_packages=() # Clear for next package block
      fi
      # Append the comment/header line as is
      output_lines+=("$line")
      in_package_block=0 # We are now in a comment/header block
    else
      # Not a comment/header line, it's a potential package line
      local trimmed_content
      # Remove leading/trailing whitespace for content check
      trimmed_content=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # If it's a non-empty line (after trimming), add it to the current package section.
      # We add the *original* line content to preserve leading whitespace.
      if [[ -n "$trimmed_content" ]]; then
        current_section_packages+=("$line")
        in_package_block=1 # We are now in a package block
      else
        # If it's an empty line (or just whitespace), process current block if active, then add the empty line.
        if [[ "$in_package_block" -eq 1 ]]; then
          local temp_sort_input=""
          for pkg_line in "${current_section_packages[@]}"; do
            local trimmed_pkg=$(echo "$pkg_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$trimmed_pkg" ]]; then
              temp_sort_input+="${trimmed_pkg}\t${pkg_line}\n"
            fi
          done

          local sorted_unique_block=()
          if [[ -n "$temp_sort_input" ]]; then
            IFS=$'\n' sorted_unique_block=($(echo -e "$temp_sort_input" | sort -t$'\t' -k1,1 | awk -F'\t' '!seen[$1]++ { print $2 }'))
          fi
          output_lines+=("${sorted_unique_block[@]}")
          current_section_packages=() # Clear for next package block
        fi
        output_lines+=("$line") # Add the original empty line
        in_package_block=0      # We are now in an empty line block, not a package block
      fi
    fi
  done <"$file_path"

  # After loop, if there are remaining package lines in the last block, sort and append them
  if [[ "$in_package_block" -eq 1 ]]; then
    local temp_sort_input=""
    for pkg_line in "${current_section_packages[@]}"; do
      local trimmed_pkg=$(echo "$pkg_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [[ -n "$trimmed_pkg" ]]; then
        temp_sort_input+="${trimmed_pkg}\t${pkg_line}\n"
      fi
    done

    local sorted_unique_block=()
    if [[ -n "$temp_sort_input" ]]; then
      IFS=$'\n' sorted_unique_block=($(echo -e "$temp_sort_input" | sort -t$'\t' -k1,1 | awk -F'\t' '!seen[$1]++ { print $2 }'))
    fi
    output_lines+=("${sorted_unique_block[@]}")
  fi

  # Write the collected and sorted lines to the temporary file
  printf "%s\n" "${output_lines[@]}" >"$temp_file"

  # Replace the original file with the sorted content
  if ! mv "$temp_file" "$file_path"; then
    echo "An error occurred while writing to the file." >&2
    return 1
  fi

  echo "File '$file_path' sorted by sections and duplicates removed successfully, preserving leading whitespace."
  return 0
}

# Function to show usage
show_usage() {
  cat <<EOF
Usage: $0 [FILE_PATH]

Sorts the content of a package list file alphabetically within sections
defined by comments/headers and removes duplicates within those sections,
while preserving the leading whitespace (indentation) of package lines.

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
