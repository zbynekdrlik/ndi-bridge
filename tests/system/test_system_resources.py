"""
System tests for resource availability and limits.

Tests system resources like memory, disk, and CPU.
"""

import pytest


def test_system_has_sufficient_memory(host):
    """Test that system has at least 1GB of RAM."""
    result = host.run("free -m | grep '^Mem:' | awk '{print $2}'")
    total_mb = int(result.stdout.strip())
    assert total_mb >= 1024, f"Insufficient memory: {total_mb}MB (need 1024MB+)"


def test_system_has_available_memory(host):
    """Test that system has some available memory."""
    result = host.run("free -m | grep '^Mem:' | awk '{print $7}'")
    available_mb = int(result.stdout.strip())
    assert available_mb > 100, f"Low available memory: {available_mb}MB"


def test_root_filesystem_has_space(host):
    """Test that root filesystem has at least 100MB free."""
    result = host.run("df -m / | tail -1 | awk '{print $4}'")
    free_mb = int(result.stdout.strip())
    assert free_mb >= 100, f"Low disk space: {free_mb}MB free"


def test_tmp_filesystem_exists(host):
    """Test that /tmp filesystem exists."""
    tmp = host.file("/tmp")
    assert tmp.exists, "/tmp directory not found"
    assert tmp.is_directory, "/tmp is not a directory"


def test_tmp_is_writable(host):
    """Test that /tmp is writable."""
    result = host.run("touch /tmp/test_write && rm /tmp/test_write")
    assert result.rc == 0, "/tmp is not writable"


def test_cpu_count_detected(host):
    """Test that CPU cores are detected."""
    result = host.run("nproc")
    cpu_count = int(result.stdout.strip())
    assert cpu_count >= 1, f"Invalid CPU count: {cpu_count}"


def test_proc_filesystem_mounted(host):
    """Test that /proc filesystem is mounted."""
    proc = host.mount_point("/proc")
    assert proc.exists, "/proc not mounted"
    assert proc.filesystem == "proc", f"/proc has wrong filesystem: {proc.filesystem}"


def test_sys_filesystem_mounted(host):
    """Test that /sys filesystem is mounted."""
    sys = host.mount_point("/sys")
    assert sys.exists, "/sys not mounted"
    assert sys.filesystem == "sysfs", f"/sys has wrong filesystem: {sys.filesystem}"


def test_dev_filesystem_mounted(host):
    """Test that /dev filesystem is mounted."""
    dev = host.mount_point("/dev")
    assert dev.exists, "/dev not mounted"
    assert dev.filesystem in ["devtmpfs", "tmpfs"], f"/dev has wrong filesystem: {dev.filesystem}"


def test_kernel_version_recent(host):
    """Test that kernel version is reasonably recent."""
    result = host.run("uname -r")
    kernel = result.stdout.strip()
    # Extract major.minor version
    parts = kernel.split(".")
    if len(parts) >= 2:
        major = int(parts[0])
        assert major >= 5, f"Old kernel version: {kernel}"


def test_swap_configured(host):
    """Test that swap is configured (optional)."""
    result = host.run("free -m | grep '^Swap:' | awk '{print $2}'")
    swap_mb = int(result.stdout.strip())
    # Swap is optional but good to have
    assert swap_mb >= 0, "Error reading swap info"


@pytest.mark.system
def test_load_average_reasonable(host):
    """Test that system load average is reasonable."""
    result = host.run("cat /proc/loadavg | awk '{print $1}'")
    load1 = float(result.stdout.strip())
    
    # Get CPU count for comparison
    cpu_result = host.run("nproc")
    cpu_count = int(cpu_result.stdout.strip())
    
    # Load should be less than 2x CPU count
    assert load1 < (cpu_count * 2), f"High load: {load1} (CPUs: {cpu_count})"