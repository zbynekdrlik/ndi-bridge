#!/usr/bin/env python3
"""
Simple test runner for NDI Bridge tests using sshpass for authentication.
"""

import sys
import os
import subprocess

def main():
    # Default host
    host = "10.77.9.188"
    if len(sys.argv) > 1 and "--host" in sys.argv[1]:
        host = sys.argv[1].split("=")[1] if "=" in sys.argv[1] else sys.argv[2]
    
    # Set environment for SSH password auth
    os.environ["SSHPASS"] = "newlevel"
    
    # Create SSH wrapper script
    ssh_wrapper = "/tmp/ssh_wrapper.sh"
    with open(ssh_wrapper, "w") as f:
        f.write("""#!/bin/bash
sshpass -e ssh -o StrictHostKeyChecking=no "$@"
""")
    os.chmod(ssh_wrapper, 0o755)
    
    # Set SSH command for testinfra
    os.environ["TESTINFRA_SSH_COMMAND"] = ssh_wrapper
    
    # Run pytest with modified environment
    cmd = [
        "python3", "-m", "pytest",
        "--host", f"ssh://root@{host}",
        "-v",
        "--skip-readonly-check"  # Skip RO check for now
    ] + sys.argv[1:]
    
    # Filter out our custom --host argument
    cmd = [arg for arg in cmd if not arg.startswith("--host")]
    
    subprocess.run(cmd)

if __name__ == "__main__":
    main()