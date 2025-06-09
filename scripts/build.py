#!/usr/bin/python

import os
import subprocess
import shutil
import argparse
import sys
from datetime import datetime
import hashlib

def _get_privilege_command():
    """
    Determines the command for privilege escalation.
    If the script is already running as root, returns an empty list.
    Otherwise, finds 'doas' or 'sudo', preferring 'doas'.
    """
    if os.geteuid() == 0:
        print("Script is running as root. Privilege escalation tool is not needed.")
        return []

    if shutil.which("doas"):
        print("Using 'doas' for privilege escalation.")
        return ["doas"]
    if shutil.which("sudo"):
        print("Using 'sudo' for privilege escalation.")
        return ["sudo"]
    
    return None

PRIV_CMD_LIST = _get_privilege_command()
if PRIV_CMD_LIST is None:
    print("Error: Not running as root, and neither 'doas' nor 'sudo' found in PATH.", file=sys.stderr)
    sys.exit(1)


def generate_iso_filename():
    """Generates the ISO filename based on Crystal Linux naming convention and current date."""
    build_date = datetime.now().strftime("%Y%m%d")
    arch = "x86_64"
    return f"CrystalLinux-{build_date}-{arch}.iso"

def update_version_file(airootfs_path):
    """Updates the Crystal Linux version file with the current date."""
    version_file = os.path.join(airootfs_path, "etc", "crystallinux-version")
    build_date = datetime.now().strftime("%Y.%m")
    try:
        with open(version_file, "w") as f:
            f.write(f"{build_date}\n")
        print(f"Updated version file: {version_file} with date {build_date}")
    except IOError as e:
        print(f"Error writing to version file {version_file}: {e}", file=sys.stderr)

def generate_checksum(file_path):
    """Generates SHA256 checksum for a given file."""
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        print(f"Error reading file for checksum: {e}", file=sys.stderr)
        return None

def _parse_args():
    """Parses command line arguments."""
    parser = argparse.ArgumentParser(description="Build Crystal Linux ISO.")
    parser.add_argument("--work-dir", default="../build/work", help="Working directory for the build (defaults to ../build/work).")
    parser.add_argument("--output-dir", default="../build/out", help="Output directory for the ISO (defaults to ../build/out).")
    parser.add_argument("-c", "--clean", action="store_true", help="Clean the work directory before building.")
    return parser.parse_args()

def _setup_paths(args):
    """Sets up and verifies necessary paths."""
    work_dir = os.path.abspath(args.work_dir)
    output_dir = os.path.abspath(args.output_dir)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    iso_dir = os.path.dirname(script_dir)
    project_root = os.path.dirname(iso_dir)
    archiso_source_dir = os.path.join(iso_dir, "archiso")
    work_archiso_dir = os.path.join(work_dir, "archiso")

    os.makedirs(os.path.dirname(work_dir), exist_ok=True)
    os.makedirs(work_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)
    
    if not os.path.exists(archiso_source_dir):
        print(f"Error: Archiso source directory not found at {archiso_source_dir}", file=sys.stderr)
        return None, None, None, None, None
    
    return work_dir, output_dir, project_root, archiso_source_dir, work_archiso_dir

def _clean_work_dir(work_dir, clean_first):
    """Cleans the work directory if requested."""
    if clean_first and os.path.exists(work_dir):
        print(f"Cleaning work directory: {work_dir}")
        try:
            # Cleaning might require root if the directory was created by a previous root-run
            command = PRIV_CMD_LIST + ["rm", "-rf", work_dir]
            subprocess.run(command, check=True, capture_output=True)
            os.makedirs(work_dir, exist_ok=True)
            return True
        except (OSError, subprocess.CalledProcessError) as e:
            print(f"Error cleaning work directory: {e}", file=sys.stderr)
            return False
    return True

def _copy_archiso_profile(archiso_source_dir, work_archiso_dir):
    """Copies the archiso profile to the work directory, preferring rsync."""
    print(f"Copying archiso profile from {archiso_source_dir} to {work_archiso_dir}")
    try:
        os.makedirs(work_archiso_dir, exist_ok=True)
        try:
            subprocess.run(["rsync", "-a", "--delete", "--exclude", ".git", f"{archiso_source_dir}/", work_archiso_dir], check=True)
            print("Archiso profile copied using rsync.")
        except (subprocess.CalledProcessError, FileNotFoundError):
             print("rsync not found or failed, falling back to shutil.copytree.")
             if os.path.exists(work_archiso_dir):
                 shutil.rmtree(work_archiso_dir)
             shutil.copytree(archiso_source_dir, work_archiso_dir)
             print("Archiso profile copied using shutil.copytree.")
        return True
    except OSError as e:
        print(f"Error copying archiso directory: {e}", file=sys.stderr)
        return False

def _run_mkarchiso(project_root, work_dir, output_dir, work_archiso_dir):
    """Executes the mkarchiso command with verbose output always enabled."""
    print(f"Starting ISO build in {work_archiso_dir}")
    original_cwd = os.getcwd()
    try:
        os.chdir(project_root)
        mkarchiso_command = PRIV_CMD_LIST + ["mkarchiso", "-v", "-w", work_dir, "-o", output_dir, work_archiso_dir]
        print(f"Executing command: {' '.join(mkarchiso_command)}")
        
        process = subprocess.Popen(mkarchiso_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        while True:
            if process.stdout:
                line = process.stdout.readline()
                if not line: break
                print(line.strip())
            else: break
        
        return_code = process.wait()
        if return_code != 0:
            print(f"mkarchiso exited with error code: {return_code}", file=sys.stderr)
            return False
        return True
    except (subprocess.CalledProcessError, OSError) as e:
        print(f"Error during mkarchiso execution: {e}", file=sys.stderr)
        return False
    finally:
        os.chdir(original_cwd)

def _process_output_iso(output_dir):
    """Finds, renames, and generates checksum for the output ISO."""
    generated_iso_name_pattern = "CrystalLinux-"
    files = sorted(
        [os.path.join(output_dir, f) for f in os.listdir(output_dir) if f.startswith(generated_iso_name_pattern) and f.endswith(".iso")],
        key=os.path.getmtime,
        reverse=True
    )
    if not files:
        print(f"Error: Could not find the generated ISO file in {output_dir}", file=sys.stderr)
        return None

    old_iso_path = files[0]
    new_iso_name = generate_iso_filename()
    new_iso_path = os.path.join(output_dir, new_iso_name)
    
    try:
        os.rename(old_iso_path, new_iso_path)
        print(f"Renamed ISO from {os.path.basename(old_iso_path)} to {os.path.basename(new_iso_path)}")
    except OSError as e:
        print(f"Error renaming ISO: {e}", file=sys.stderr)
        return None
    
    if os.path.exists(new_iso_path):
        print(f"Generating SHA256 checksum for {new_iso_path}")
        checksum = generate_checksum(new_iso_path)
        if checksum:
            checksum_file_path = f"{new_iso_path}.sha256"
            try:
                with open(checksum_file_path, "w") as f:
                    f.write(f"{checksum}  {os.path.basename(new_iso_path)}\n")
                print(f"Checksum saved to {checksum_file_path}")
            except IOError as e: 
                print(f"Error saving checksum file: {e}", file=sys.stderr)
        else: 
            print("Failed to generate checksum.", file=sys.stderr)
    else:
         print(f"Error: Final ISO file not found at {new_iso_path} for checksumming.", file=sys.stderr)
         return None
    
    return new_iso_path

def _handle_ownership(output_dir):
    """Attempts to change ownership of the output directory to the original user."""
    # `SUDO_USER` is set by sudo/doas. If it's not set, we're likely the correct user already.
    sudo_user = os.environ.get('SUDO_USER')
    if not sudo_user:
        print("Not running under sudo/doas, or original user not detected. Skipping ownership change.")
        return True

    print(f"Attempting to change ownership of {output_dir} to user '{sudo_user}'...")
    try:
        command = PRIV_CMD_LIST + ["chown", "-R", sudo_user, output_dir]
        subprocess.run(command, check=True)
        print("Ownership changed successfully.")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
         print(f"Warning: Could not change ownership of {output_dir}.", file=sys.stderr)
         if isinstance(e, subprocess.CalledProcessError):
             print(f"Command failed: {' '.join(e.cmd)}", file=sys.stderr)
             if e.stderr: print(f"Stderr: {e.stderr.strip()}", file=sys.stderr)
         return False
    except Exception as e:
        print(f"An unexpected error occurred while trying to change ownership: {e}", file=sys.stderr)
        return False

def _copy_package_list(work_dir, output_dir, final_iso_path):
    """Copies the generated package list to the output directory."""
    package_list_source = os.path.join(work_dir, "iso", "arch", "pkglist.x86_64.txt")
    if final_iso_path:
        package_list_dest = os.path.join(output_dir, f"{os.path.splitext(os.path.basename(final_iso_path))[0]}.pkgs.txt")
    else:
        package_list_dest = os.path.join(output_dir, "pkglist.x86_64.txt")
    
    if os.path.exists(package_list_source):
        print(f"Copying package list to {package_list_dest}")
        try:
            shutil.copy(package_list_source, package_list_dest)
            return package_list_dest
        except IOError as e:
            print(f"Error copying package list: {e}", file=sys.stderr)
    else:
        print(f"Warning: Package list file not found at {package_list_source}", file=sys.stderr)
    
    return None

def main_build():
    """Main function to orchestrate the Crystal Linux ISO build process."""
    args = _parse_args()
    
    setup_result = _setup_paths(args)
    if setup_result is None or not all(setup_result):
        print("Failed to set up paths. Exiting.", file=sys.stderr)
        return

    work_dir, output_dir, project_root, archiso_source_dir, work_archiso_dir = setup_result
    
    if not _clean_work_dir(work_dir, args.clean):
        print("Failed to clean work directory. Exiting.", file=sys.stderr)
        return

    if not _copy_archiso_profile(archiso_source_dir, work_archiso_dir):
        print("Failed to copy archiso profile. Exiting.", file=sys.stderr)
        return

    update_version_file(os.path.join(work_archiso_dir, "airootfs"))
    
    if not _run_mkarchiso(project_root, work_dir, output_dir, work_archiso_dir):
        print("mkarchiso build failed. Exiting.", file=sys.stderr)
        return

    final_iso_path = _process_output_iso(output_dir)
    
    if final_iso_path:
        _handle_ownership(output_dir)
        package_list_dest = _copy_package_list(work_dir, output_dir, final_iso_path)
        
        print("\nBuild process completed.")
        print(f"Final ISO located at: {final_iso_path}")
        if package_list_dest:
            print(f"Package list located at: {package_list_dest}")
    else:
        print("\nISO output processing failed. The build may not have completed successfully.", file=sys.stderr)

if __name__ == "__main__":
    main_build()