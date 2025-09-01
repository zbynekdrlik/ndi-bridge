#!/usr/bin/env python3
"""
Simple test runner for NDI Bridge tests using sshpass for authentication.

Usage:
    python3 run_test.py --host=10.77.9.188
    
Or using environment variable:
    export NDI_TEST_HOST=10.77.9.188
    python3 run_test.py
"""

import sys
import os
import subprocess

def main():
    # Determine host from: 1) command line, 2) environment, 3) default
    host = None
    
    # Check command line arguments
    for i, arg in enumerate(sys.argv):
        if arg.startswith("--host="):
            host = arg.split("=")[1]
            break
        elif arg == "--host" and i + 1 < len(sys.argv):
            host = sys.argv[i + 1]
            break
    
    # Fall back to environment variable
    if not host:
        host = os.environ.get("NDI_TEST_HOST")
    
    # Fall back to default
    if not host:
        host = "10.77.9.143"
        print(f"Warning: No host specified. Using default: {host}")
        print("Set NDI_TEST_HOST environment variable or use --host=IP_ADDRESS")
    
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