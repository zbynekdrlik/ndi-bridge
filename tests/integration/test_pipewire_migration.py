"""
Tests for PipeWire user migration script and process.

Verifies the migration from root to mediabridge user works correctly.
"""

import pytest
import time


def test_migration_script_exists(host):
    """Test that migration script is installed."""
    script = host.file("/usr/local/bin/migrate-pipewire-user.sh")
    assert script.exists, "Migration script not found"
    assert script.mode == 0o755, "Migration script not executable"
    assert script.user == "root", "Migration script not owned by root"


def test_migration_script_syntax(host):
    """Test that migration script has valid bash syntax."""
    result = host.run("bash -n /usr/local/bin/migrate-pipewire-user.sh")
    assert result.exit_status == 0, f"Migration script has syntax errors: {result.stderr}"


def test_post_migration_user_exists(host):
    """Test that mediabridge user exists after migration."""
    user = host.user("mediabridge")
    assert user.exists, "mediabridge user not created"
    assert user.uid == 999, f"Wrong UID: {user.uid}"
    assert user.gid in [994, 29, 995], f"Wrong GID: {user.gid} (should be audio group)"


def test_post_migration_directories(host):
    """Test that all required directories exist after migration."""
    directories = [
        "/run/pipewire",
        "/var/lib/mediabridge",
        "/var/lib/mediabridge/.config",
        "/var/lib/mediabridge/.config/systemd/user",
        "/var/lib/mediabridge/.config/wireplumber",
        "/var/lib/mediabridge/chrome-profile",
        "/var/run/ndi-display",
        "/var/run/media-bridge"
    ]
    
    for dir_path in directories:
        dir_obj = host.file(dir_path)
        assert dir_obj.exists, f"Directory {dir_path} not created"
        assert dir_obj.is_directory, f"{dir_path} is not a directory"


def test_post_migration_ownership(host):
    """Test that directories have correct ownership."""
    dirs_to_check = [
        ("/var/lib/mediabridge", "mediabridge", "audio"),
        ("/var/lib/mediabridge/chrome-profile", "mediabridge", "audio"),
        ("/run/pipewire", "mediabridge", "audio"),
    ]
    
    for path, expected_user, expected_group in dirs_to_check:
        file_obj = host.file(path)
        if file_obj.exists:
            assert file_obj.user == expected_user, f"{path} owned by {file_obj.user}, not {expected_user}"
            assert file_obj.group == expected_group, f"{path} group is {file_obj.group}, not {expected_group}"


def test_post_migration_limits_conf(host):
    """Test that limits.conf is created."""
    limits = host.file("/etc/security/limits.d/99-mediabridge.conf")
    assert limits.exists, "Limits configuration not created"
    
    content = limits.content_string
    assert "mediabridge   -  rtprio     95" in content, "mediabridge rtprio not set"
    assert "@audio   -  rtprio     95" in content, "audio group rtprio not set"


def test_post_migration_tmpfiles(host):
    """Test that tmpfiles.d configuration is created."""
    tmpfiles = host.file("/etc/tmpfiles.d/mediabridge.conf")
    assert tmpfiles.exists, "tmpfiles.d configuration not created"
    
    content = tmpfiles.content_string
    assert "/run/pipewire" in content
    assert "/run/user/999" in content
    assert "mediabridge" in content


def test_post_migration_service_overrides(host):
    """Test that PipeWire user service overrides are created."""
    override = host.file("/var/lib/mediabridge/.config/systemd/user/pipewire.service.d/override.conf")
    assert override.exists, "PipeWire service override not created"
    
    content = override.content_string
    assert "mount --bind" in content, "Bind mount command not in override"
    assert "/run/user/999/pipewire-0" in content
    assert "/run/pipewire/pipewire-0" in content


def test_post_migration_wireplumber_config(host):
    """Test that WirePlumber Chrome isolation is configured."""
    config = host.file("/var/lib/mediabridge/.config/wireplumber/wireplumber.conf.d/50-chrome-isolation.conf")
    assert config.exists, "WirePlumber Chrome config not created"
    
    content = config.content_string
    assert "chrome" in content
    assert "intercom-speaker" in content


def test_post_migration_services_updated(host):
    """Test that systemd services are updated."""
    # Check intercom service
    result = host.run("systemctl show media-bridge-intercom -p User")
    user = result.stdout.strip().split('=')[1] if '=' in result.stdout else ""
    assert user == "mediabridge", f"Intercom service not updated to mediabridge user: {user}"
    
    # Check environment
    result = host.run("systemctl show media-bridge-intercom -p Environment")
    assert "XDG_RUNTIME_DIR=/run/pipewire" in result.stdout


def test_post_migration_old_services_disabled(host):
    """Test that old system services are disabled."""
    old_services = ["pipewire-system", "pipewire-pulse-system", "wireplumber-system"]
    
    for service_name in old_services:
        service = host.service(service_name)
        assert not service.is_enabled, f"{service_name} still enabled"
        assert not service.is_running, f"{service_name} still running"


def test_post_migration_user_services_enabled(host):
    """Test that user services are enabled."""
    # Check if services are enabled for mediabridge user
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user is-enabled pipewire")
    assert "enabled" in result.stdout, "PipeWire user service not enabled"
    
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user is-enabled pipewire-pulse")
    assert "enabled" in result.stdout, "PipeWire-Pulse user service not enabled"
    
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user is-enabled wireplumber")
    assert "enabled" in result.stdout, "WirePlumber user service not enabled"


def test_post_migration_scripts_updated(host):
    """Test that helper scripts are updated with new paths."""
    scripts_to_check = [
        "/usr/local/bin/media-bridge-audio-manager",
        "/usr/local/bin/media-bridge-intercom-control",
        "/usr/local/bin/ndi-display-launcher"
    ]
    
    for script_path in scripts_to_check:
        script = host.file(script_path)
        if script.exists:
            content = script.content_string
            assert "/run/pipewire" in content, f"{script_path} not updated to /run/pipewire"
            assert "/run/user/0" not in content, f"{script_path} still has /run/user/0"
            
            # Check for new Chrome profile path
            if "chrome" in script_path.lower() or "intercom" in script_path.lower():
                assert "/tmp/chrome-vdo-profile" not in content, f"{script_path} still has old Chrome path"


def test_post_migration_environment_updated(host):
    """Test that /etc/environment is updated."""
    env_file = host.file("/etc/environment")
    content = env_file.content_string
    
    assert "XDG_RUNTIME_DIR=/run/pipewire" in content, "XDG_RUNTIME_DIR not updated"
    assert "PIPEWIRE_RUNTIME_DIR=/run/pipewire" in content, "PIPEWIRE_RUNTIME_DIR not added"
    assert "PULSE_RUNTIME_PATH=/run/pipewire/pulse" in content, "PULSE_RUNTIME_PATH not added"
    assert "/run/user/0" not in content, "Old /run/user/0 still in environment"


def test_post_migration_chrome_profile_moved(host):
    """Test that Chrome profile is moved to new location."""
    new_profile = host.file("/var/lib/mediabridge/chrome-profile")
    assert new_profile.exists, "Chrome profile not in new location"
    assert new_profile.is_directory, "Chrome profile is not a directory"
    assert new_profile.user == "mediabridge", "Chrome profile not owned by mediabridge"
    
    # Old locations should not exist
    old_locations = ["/tmp/chrome-vdo-profile", "/opt/chrome-vdo-profile"]
    for old_path in old_locations:
        old_profile = host.file(old_path)
        assert not old_profile.exists, f"Chrome profile still in old location: {old_path}"


def test_post_migration_loginctl_linger(host):
    """Test that loginctl linger is enabled."""
    linger = host.file("/var/lib/systemd/linger/mediabridge")
    assert linger.exists, "loginctl linger not enabled for mediabridge"


def test_migration_idempotent(host):
    """Test that running migration twice doesn't break things."""
    # Run migration script (it should handle being run multiple times)
    result = host.run("/usr/local/bin/migrate-pipewire-user.sh", timeout=60)
    
    # Even if it's already migrated, script should handle it gracefully
    # Check that services still work
    time.sleep(5)
    
    # Verify PipeWire is still running
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user is-active pipewire")
    assert "active" in result.stdout, "PipeWire not active after re-migration"


@pytest.mark.slow
def test_post_migration_reboot_persistence(host):
    """Test that configuration persists after reboot."""
    # This test would require actual reboot capability
    # Mark as slow and optional
    
    # Check that all enable symlinks exist
    symlinks = [
        "/etc/systemd/system/multi-user.target.wants/media-bridge-intercom.service",
        "/var/lib/mediabridge/.config/systemd/user/default.target.wants/pipewire.service",
        "/var/lib/mediabridge/.config/systemd/user/default.target.wants/wireplumber.service"
    ]
    
    for link_path in symlinks:
        link = host.file(link_path)
        if link.exists:
            assert link.is_symlink, f"{link_path} is not a symlink"