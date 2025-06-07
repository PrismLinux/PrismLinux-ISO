#!/usr/bin/python

import os

def format_packages(file_path):
    """
    Formats the content of a package list file alphabetically and removes duplicates.

    Args:
        file_path (str): The path to the package list file.
    """
    try:
        # Get the absolute path to the file
        file_path = os.path.abspath(file_path)

        with open(file_path, 'r') as f:
            # Read lines and remove leading/trailing whitespace, filter out empty lines
            packages = [line.strip() for line in f.read().splitlines() if line.strip()]

        # Remove duplicates by converting to a set and back to a list
        unique_packages = list(set(packages))

        # Sort the unique packages alphabetically
        sorted_packages = sorted(unique_packages)

        with open(file_path, 'w') as f:
            # Write sorted, unique packages back to the file
            f.write('\n'.join(sorted_packages) + '\n')

        print(f"File '{file_path}' formatted and duplicates removed successfully.")
    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    file_path = "../archiso/packages.x86_64"
    format_packages(file_path)
