"""
Tests for PipeWire 1.4.7 version verification.

Ensures that PipeWire 1.4.7 from Rob Savoury's PPA is correctly installed.
"""

import pytest


def test_pipewire_version_is_1_4_7(host):
    """Test that PipeWire version is 1.4.7."""
    result = host.run("pipewire --version")
    assert result.rc == 0, "Failed to get PipeWire version"
    # Check for version 1.4.7 in output
    output_lines = result.stdout.strip().split('\n')
    version_found = False
    for line in output_lines:
        if "1.4.7" in line:
            version_found = True
            break
    assert version_found, f"PipeWire version is not 1.4.7. Output: {result.stdout}"


def test_pw_container_tool_available(host):
    """Test that pw-container tool is available (PipeWire 1.4.7 feature)."""
    result = host.run("which pw-container")
    assert result.rc == 0, "pw-container tool not found (requires PipeWire 1.4.7)"
    assert "/usr/bin/pw-container" in result.stdout, f"pw-container in unexpected location: {result.stdout}"


def test_pipewire_packages_version(host):
    """Test that all PipeWire packages are version 1.4.7 from Savoury PPA."""
    result = host.run("dpkg -l | grep pipewire | awk '{print $2, $3}'")
    assert result.rc == 0, "Failed to list PipeWire packages"
    
    packages_checked = 0
    for line in result.stdout.strip().split('\n'):
        if line and 'pipewire' in line:
            parts = line.split()
            if len(parts) >= 2:
                package, version = parts[0], parts[1]
                assert "1.4.7" in version, f"Package {package} is not version 1.4.7: {version}"
                assert "sav0" in version, f"Package {package} not from Savoury PPA: {version}"
                packages_checked += 1
    
    assert packages_checked > 0, "No PipeWire packages found to verify"


def test_pipewire_version_pinning(host):
    """Test that PipeWire packages are pinned to prevent downgrades."""
    pin_file = host.file("/etc/apt/preferences.d/pipewire-pin")
    assert pin_file.exists, "PipeWire version pinning file not found"
    
    content = pin_file.content_string
    assert "1.4.7-0ubuntu1~24.04.sav0" in content, "Version pin not set to 1.4.7"
    assert "Pin-Priority: 1001" in content, "Pin priority not high enough"


@pytest.mark.critical
def test_pipewire_upgrade_from_default(host):
    """Test that PipeWire was upgraded from Ubuntu's default 1.0.5."""
    # Check that we're not running the default Ubuntu version
    result = host.run("apt-cache policy pipewire | grep -E 'Installed|Candidate'")
    assert result.rc == 0
    
    # Verify installed version is from PPA
    assert "1.4.7" in result.stdout, "PipeWire not upgraded to 1.4.7"
    assert "sav0" in result.stdout, "PipeWire not from Savoury PPA"
    
    # Make sure default Ubuntu version is not installed
    assert "1.0.5" not in result.stdout or "Installed" not in result.stdout.split("1.0.5")[0], \
        "Ubuntu's default PipeWire 1.0.5 is still installed"