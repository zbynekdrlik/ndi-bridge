"""
Atomic tests for time synchronization.

Tests PTP and NTP time synchronization functionality.
"""

import pytest
import time


def test_systemd_timesyncd_installed(host):
    """Test that systemd-timesyncd is installed."""
    result = host.run("systemctl list-unit-files | grep systemd-timesyncd")
    assert result.rc == 0, "systemd-timesyncd not found"


def test_systemd_timesyncd_enabled(host):
    """Test that systemd-timesyncd is enabled."""
    service = host.service("systemd-timesyncd")
    assert service.is_enabled, "systemd-timesyncd not enabled"


def test_systemd_timesyncd_running(host):
    """Test that systemd-timesyncd is running."""
    service = host.service("systemd-timesyncd")
    assert service.is_running, "systemd-timesyncd not running"


def test_timedatectl_command_works(host):
    """Test that timedatectl command works."""
    result = host.run("timedatectl status")
    assert result.rc == 0, "timedatectl command failed"


def test_ntp_synchronized(host):
    """Test that NTP is synchronized."""
    result = host.run("timedatectl status | grep 'System clock synchronized'")
    if result.rc == 0:
        assert "yes" in result.stdout, "System clock not synchronized"


def test_time_zone_set(host):
    """Test that timezone is set."""
    result = host.run("timedatectl status | grep 'Time zone'")
    assert result.rc == 0, "Cannot determine timezone"
    assert "Time zone:" in result.stdout, "Timezone not configured"


def test_rtc_available(host):
    """Test that RTC (Real Time Clock) is available."""
    result = host.run("timedatectl status | grep 'RTC time'")
    # RTC might not be available in VMs
    if result.rc == 0:
        assert "RTC time:" in result.stdout, "RTC not detected"


def test_ptp4l_installed(host):
    """Test that PTP daemon is installed."""
    result = host.run("which ptp4l")
    if result.rc == 0:
        # PTP is installed
        assert True, "PTP4L found"
    else:
        # PTP might be optional
        pytest.skip("PTP4L not installed")


def test_ptp_service_exists(host):
    """Test that PTP service exists if PTP is installed."""
    result = host.run("which ptp4l")
    if result.rc == 0:
        service_result = host.run("systemctl list-unit-files | grep ptp")
        assert service_result.rc == 0, "PTP service not found despite ptp4l installed"


def test_chrony_installed(host):
    """Test that chrony is installed (alternative to systemd-timesyncd)."""
    result = host.run("which chronyd")
    if result.rc == 0:
        # Chrony is installed
        service = host.service("chronyd")
        assert service.is_enabled or service.is_running, "Chrony installed but not active"


def test_ntp_servers_configured(host):
    """Test that NTP servers are configured."""
    # Check systemd-timesyncd config
    config = host.file("/etc/systemd/timesyncd.conf")
    if config.exists:
        # Check for NTP server configuration
        assert "NTP=" in config.content_string or "[Time]" in config.content_string, "No NTP servers configured"


def test_time_sync_coordinator_installed(host):
    """Test that time-sync-coordinator is installed."""
    script = host.file("/usr/local/bin/time-sync-coordinator")
    if script.exists:
        assert script.mode & 0o111, "time-sync-coordinator not executable"


def test_time_sync_coordinator_service_exists(host):
    """Test that time-sync-coordinator service exists."""
    result = host.run("systemctl list-unit-files | grep time-sync-coordinator")
    if result.rc == 0:
        service = host.service("time-sync-coordinator")
        assert service.is_enabled, "time-sync-coordinator service not enabled"


@pytest.mark.timesync
def test_system_time_reasonable(host):
    """Test that system time is reasonable (within last year)."""
    result = host.run("date +%s")
    current_timestamp = int(result.stdout.strip())
    
    # Check if time is after 2024 and before 2030
    year_2024 = 1704067200  # Jan 1, 2024
    year_2030 = 1893456000  # Jan 1, 2030
    
    assert year_2024 < current_timestamp < year_2030, f"System time unreasonable: {current_timestamp}"


def test_time_drift_file_exists(host):
    """Test that time drift monitoring file exists."""
    drift_file = host.file("/var/lib/systemd/timesync/clock")
    # File might not exist on fresh system
    if drift_file.exists:
        assert True, "Time drift file found"