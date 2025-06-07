#!/usr/bin/python

import os
import subprocess
import shutil
import argparse
from datetime import datetime
import hashlib

def generate_iso_filename():
    """Generates the ISO filename based on Crystal Linux naming convention and current date."""
    build_date = datetime.now().strftime("%Y%m%d")
    arch = "x86_64" # Based on profiledef.sh
    return f"CrystalLinux-{build_date}-{arch}.iso"

def update_version_file(airootfs_path):
    """Updates the Crystal Linux version file with the current date."""
    version_file = os.path.join(airootfs_path, "etc", "crystallinux-version")
    # Using YYYY.MM format as seen in ISO/archiso/profiledef.sh iso_version
    build_date = datetime.now().strftime("%Y.%m")
    try:
        with open(version_file, "w") as f:
            f.write(f"{build_date}\n")
        print(f"Updated version file: {version_file} with date {build_date}")
    except IOError as e:
        print(f"Error writing to version file {version_file}: {e}")

def generate_checksum(file_path):
    """Generates SHA256 checksum for a given file."""
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            # Read and update hash string value in blocks of 4K
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        print(f"Error reading file for checksum: {e}")
        return None

def _parse_args():
    """Parses command line arguments."""
    parser = argparse.ArgumentParser(description="Build Crystal Linux ISO.")
    # Changed default paths to be inside a 'build' directory at the root
    parser.add_argument("--work-dir", default="../build/work", help="Working directory for the build (defaults to ../build/work).")
    parser.add_argument("--output-dir", default="../build/out", help="Output directory for the ISO (defaults to ../build/out).")
    parser.add_argument("-c", "--clean", action="store_true", help="Clean the work directory before building.")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose output.")
    return parser.parse_args()

def _setup_paths(args):
    """Sets up and verifies necessary paths."""
    work_dir = os.path.abspath(args.work_dir)
    output_dir = os.path.abspath(args.output_dir)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    iso_dir = os.path.dirname(script_dir) # Path to the ISO directory
    project_root = os.path.dirname(iso_dir) # Path to the project root (containing ISO and build)

    archiso_source_dir = os.path.join(iso_dir, "archiso")
    work_archiso_dir = os.path.join(work_dir, "archiso") # Archiso profile inside the work directory

    # Create the build, work, and out directories if they don't exist
    os.makedirs(os.path.dirname(work_dir), exist_ok=True) # Create the parent build directory
    os.makedirs(work_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)

    if not os.path.exists(archiso_source_dir):
        print(f"Error: Archiso source directory not found at {archiso_source_dir}")
        return None, None, None, None, None

    return work_dir, output_dir, project_root, archiso_source_dir, work_archiso_dir

def _clean_work_dir(work_dir, clean_first):
    """Cleans the work directory if requested."""
    if clean_first and os.path.exists(work_dir):
        print(f"Cleaning work directory: {work_dir}")
        try:
            shutil.rmtree(work_dir)
            # Recreate the work directory after cleaning
            os.makedirs(work_dir, exist_ok=True)
            return True
        except OSError as e:
            print(f"Error cleaning work directory: {e}")
            return False
    return True # No cleaning requested or directory didn't exist

def _copy_archiso_profile(archiso_source_dir, work_archiso_dir):
    """Copies the archiso profile to the work directory."""
    print(f"Copying archiso source from {archiso_source_dir} to {work_archiso_dir}")
    try:
        # Ensure the destination exists before copying
        os.makedirs(work_archiso_dir, exist_ok=True)
        # Use rsync for potentially more robust copying of permissions, etc.,
        # or fallback to shutil.copytree
        try:
            # Add --delete to rsync to ensure destination is clean if it existed
            subprocess.run(["rsync", "-a", "--delete", "--exclude", ".git", f"{archiso_source_dir}/", work_archiso_dir], check=True)
            print("Archiso profile copied using rsync.")
        except (subprocess.CalledProcessError, FileNotFoundError):
             print("rsync not found or failed, falling back to shutil.copytree.")
             # Remove existing directory if it exists, as copytree expects it not to.
             if os.path.exists(work_archiso_dir):
                 shutil.rmtree(work_archiso_dir)
             shutil.copytree(archiso_source_dir, work_archiso_dir)
             print("Archiso profile copied using shutil.copytree.")
        return True
    except OSError as e:
        print(f"Error copying archiso directory: {e}")
        return False

def _run_mkarchiso(project_root, work_dir, output_dir, work_archiso_dir, verbose):
    """Executes the mkarchiso command."""
    print(f"Starting ISO build in {work_archiso_dir}")
    original_cwd = os.getcwd()
    try:
        # mkarchiso expects the archiso profile directory as the last argument
        # and the -w and -o paths are relative to the cwd where mkarchiso is run,
        # or absolute. We are using absolute paths here and changing to project_root
        # just in case relative paths were intended somewhere implicitly by mkarchiso,
        # though absolute paths should be fine regardless of CWD.
        os.chdir(project_root)

        mkarchiso_command = ["sudo", "mkarchiso"]
        if verbose:
            mkarchiso_command.append("-v")
        mkarchiso_command.extend(["-w", work_dir, "-o", output_dir, work_archiso_dir]) # Use absolute paths

        # Fix syntax errors in f-string: remove escaped quotes
        print(f"Executing command: {' '.join(mkarchiso_command)}")
        # Use Popen for potentially real-time output handling if verbose
        # For simplicity here, keeping run but adding more robust error output
        process = subprocess.Popen(mkarchiso_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

        while True:
            if process.stdout:
                line = process.stdout.readline()
                if not line:
                    break
                print(line.strip())
            else:
                break

        return_code = process.wait()

        if return_code != 0:
            print(f"mkarchiso exited with error code: {return_code}")
            return False
        return True
    # Fix syntax errors in f-string: remove escaped quotes
    except subprocess.CalledProcessError as e:
        print(f"Error during mkarchiso execution: {e}")
        return False
    except OSError as e:
        print(f"Error changing directory or executing command: {e}")
        return False
    finally:
        os.chdir(original_cwd) # Always return to original directory

def _process_output_iso(output_dir):
    """Finds, renames, and generates checksum for the output ISO."""
    # The ISO is created in output_dir, mkarchiso names it based on profiledef.sh iso_name and date
    # Let's find the actual file name created by mkarchiso in the output directory
    generated_iso_name_pattern = "CrystalLinux-" # Based on profiledef.sh iso_name
    # List files and sort by modification time descending to get the latest ISO
    files = sorted(
        [os.path.join(output_dir, f) for f in os.listdir(output_dir) if f.startswith(generated_iso_name_pattern) and f.endswith(".iso")],
        key=os.path.getmtime,
        reverse=True
    )

    if files:
        # Get the most recently modified ISO matching the pattern
        old_iso_path = files[0]
    else:
        print(f"Error: Could not find the generated ISO file in {output_dir} matching pattern '{generated_iso_name_pattern}*.iso'")
        return None # Indicate failure

    # Generate the desired new name based on our function, which uses the current date
    # This might differ slightly from mkarchiso's name if the build spans midnight,
    # but it ensures a consistent naming convention for the final output.
    new_iso_name = generate_iso_filename()
    new_iso_path = os.path.join(output_dir, new_iso_name)

    # Rename the ISO
    try:
        os.rename(old_iso_path, new_iso_path)
        print(f"Renamed ISO from {old_iso_path} to {new_iso_path}")
    except OSError as e:
        print(f"Error renaming ISO: {e}")
        return None

    # Generate checksum for the final ISO file
    if os.path.exists(new_iso_path):
        print(f"Generating SHA256 checksum for {new_iso_path}")
        checksum = generate_checksum(new_iso_path)
        if checksum:
            checksum_file_path = f"{new_iso_path}.sha256"
            try:
                with open(checksum_file_path, "w") as f:
                    # Write checksum followed by filename, as is common
                    f.write(f"{checksum}  {os.path.basename(new_iso_path)}\n") # Two spaces before filename is standard
                print(f"Checksum saved to {checksum_file_path}")
            except IOError as e:
                print(f"Error saving checksum file: {e}")
        else:
            print("Failed to generate checksum.")
    else:
         print(f"Error: Final ISO file not found at {new_iso_path} for checksumming.")
         return None # Indicate failure

    return new_iso_path # Return the final path of the ISO

def _handle_ownership(output_dir):
    """Attempts to change ownership of the output directory to the current user."""
    print(f"Attempting to change ownership of {output_dir} to current user...")
    try:
        # Get current user ID and group ID
        # These calls might raise AttributeError on non-Unix systems
        uid = os.geteuid()
        gid = os.getegid()

        try:
            # This might require the script to be run with sufficient permissions
            subprocess.run(["sudo", "chown", "-R", f"{uid}:{gid}", output_dir], check=True)
            print("Ownership changed successfully.")
            return True
        except subprocess.CalledProcessError as e:
             print(f"Warning: Could not change ownership of {output_dir} to current user ({uid}:{gid}). Manual intervention may be required.")
             print(f"Command failed: {' '.join(e.cmd)}")
             print(f"Stderr: {e.stderr.strip()}")
             return False
        except FileNotFoundError:
             print("Warning: 'sudo' command not found. Could not change ownership. Manual intervention may be required.")
             return False

    except AttributeError:
         print("Warning: Could not get current user ID/group ID (geteuid/getegid) on this system. Skipping ownership change.")
         return False
    except Exception as e: # Catch other potential errors during geteuid/getegid or initial sudo setup
        print(f"An unexpected error occurred while trying to change ownership: {e}")
        return False


def _copy_package_list(work_dir, output_dir, final_iso_path):
    """Copies the generated package list to the output directory."""
    # Copy package list (assuming mkarchiso places it in work_dir/iso/arch/)
    package_list_source = os.path.join(work_dir, "iso", "arch", "pkglist.x86_64.txt")
    # Place package list next to the final ISO in the output directory
    # Use the final ISO name prefix for the package list file
    if final_iso_path:
        package_list_dest = os.path.join(output_dir, f"{os.path.splitext(os.path.basename(final_iso_path))[0]}.pkgs.txt")
    else:
        # Fallback name if ISO path wasn't determined
        package_list_dest = os.path.join(output_dir, "pkglist.x86_64.txt")


    if os.path.exists(package_list_source):
        print(f"Copying package list from {package_list_source} to {package_list_dest}")
        try:
            shutil.copy(package_list_source, package_list_dest)
            print("Package list copied successfully.")
            return package_list_dest
        except IOError as e:
            print(f"Error copying package list: {e}")
            return None
    else:
        print(f"Warning: Package list file not found at {package_list_source}")
        return None

def main_build():
    """Main function to orchestrate the Crystal Linux ISO build process."""
    args = _parse_args()
    verbose = args.verbose
    clean_first = args.clean

    # Call setup paths and check if all returned values are valid strings
    setup_result = _setup_paths(args)
    if setup_result is None or not all(setup_result):
        print("Failed to set up paths. Exiting.")
        return

    # Unpack the validated paths
    work_dir, output_dir, project_root, archiso_source_dir, work_archiso_dir = setup_result

    if not _clean_work_dir(work_dir, clean_first):
        print("Failed to clean work directory. Exiting.")
        return

    if not _copy_archiso_profile(archiso_source_dir, work_archiso_dir):
        print("Failed to copy archiso profile. Exiting.")
        return

    # Add assertion to satisfy type checker that work_archiso_dir is str.
    # The check `not all(setup_result)` already ensures it's not None,
    # but unpacking combined with the check can confuse type checkers.
    assert isinstance(work_archiso_dir, str), "Internal Error: work_archiso_dir is not a string after setup."


    # Update the version file in the work directory before building
    # work_archiso_dir is guaranteed to be a string here due to the assertion/previous checks
    update_version_file(os.path.join(work_archiso_dir, "airootfs"))

    if not _run_mkarchiso(project_root, work_dir, output_dir, work_archiso_dir, verbose):
        print("mkarchiso build failed. Exiting.")
        return # Exit if mkarchiso fails

    final_iso_path = _process_output_iso(output_dir)

    if final_iso_path:
        _handle_ownership(output_dir) # Attempt ownership change regardless of success

        package_list_dest = _copy_package_list(work_dir, output_dir, final_iso_path)

        # Removed 'f' as it had no placeholders
        print("\nBuild process completed.")
        print(f"Final ISO located at: {final_iso_path}")
        if package_list_dest:
            print(f"Package list located at: {package_list_dest}")
    else:
        print("\nISO output processing failed. The build may not have completed successfully.")



if __name__ == "__main__":
    main_build()
