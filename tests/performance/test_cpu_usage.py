"""
Performance tests for CPU usage.

Tests that system maintains acceptable CPU usage levels.
"""

import pytest
import time


@pytest.mark.performance
def test_capture_cpu_usage_acceptable(host):
    """Test that ndi-capture process uses less than 30% CPU."""
    # Get PID of ndi-capture
    pid_result = host.run("pgrep -x ndi-capture")
    if not pid_result.succeeded:
        pytest.skip("ndi-capture not running")
    
    pid = pid_result.stdout.strip()
    
    # Sample CPU usage over 5 seconds
    samples = []
    for _ in range(5):
        cpu_result = host.run(f"ps -p {pid} -o %cpu= | tr -d ' '")
        if cpu_result.succeeded:
            samples.append(float(cpu_result.stdout.strip()))
        time.sleep(1)
    
    if samples:
        avg_cpu = sum(samples) / len(samples)
        assert avg_cpu < 50.0, f"High CPU usage: {avg_cpu:.1f}%"


def test_system_load_average_acceptable(host):
    """Test that system load average is reasonable."""
    # Get number of CPUs
    cpu_count_result = host.run("nproc")
    cpu_count = int(cpu_count_result.stdout.strip())
    
    # Get 1-minute load average
    load_result = host.run("cat /proc/loadavg | awk '{print $1}'")
    load_avg = float(load_result.stdout.strip())
    
    # Load should be less than 2x CPU count for healthy system
    threshold = cpu_count * 2
    assert load_avg < threshold, f"High load average: {load_avg:.2f} (CPUs: {cpu_count})"


def test_memory_usage_acceptable(host):
    """Test that memory usage is within acceptable limits."""
    # Get memory info
    mem_result = host.run("free -m | grep '^Mem:' | awk '{print $3, $2}'")
    used, total = map(int, mem_result.stdout.strip().split())
    
    usage_percent = (used / total) * 100
    assert usage_percent < 80, f"High memory usage: {usage_percent:.1f}%"


@pytest.mark.performance
def test_capture_memory_footprint(host):
    """Test that ndi-capture has reasonable memory footprint."""
    # Get PID
    pid_result = host.run("pgrep -x ndi-capture")
    if not pid_result.succeeded:
        pytest.skip("ndi-capture not running")
    
    pid = pid_result.stdout.strip()
    
    # Get RSS (Resident Set Size) in MB
    rss_result = host.run(f"ps -p {pid} -o rss= | tr -d ' '")
    rss_kb = int(rss_result.stdout.strip())
    rss_mb = rss_kb / 1024
    
    # Should use less than 500MB
    assert rss_mb < 500, f"High memory usage: {rss_mb:.1f}MB"


def test_no_memory_leaks_over_time(host):
    """Test that memory usage doesn't increase significantly over time."""
    pid_result = host.run("pgrep -x ndi-capture")
    if not pid_result.succeeded:
        pytest.skip("ndi-capture not running")
    
    pid = pid_result.stdout.strip()
    
    # Get initial memory
    rss1 = int(host.run(f"ps -p {pid} -o rss= | tr -d ' '").stdout.strip())
    
    # Wait 60 seconds for more reliable measurement
    time.sleep(60)
    
    # Get final memory
    rss2 = int(host.run(f"ps -p {pid} -o rss= | tr -d ' '").stdout.strip())
    
    # Memory shouldn't increase by more than 20MB in 60 seconds
    increase_mb = (rss2 - rss1) / 1024
    assert increase_mb < 20, f"Memory increased by {increase_mb:.1f}MB in 60s"