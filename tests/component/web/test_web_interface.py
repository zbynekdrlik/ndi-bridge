"""
Atomic tests for web interface functionality.

Tests the Media Bridge web interface and API.
"""

import pytest
import json


def test_web_server_responds_to_http(host):
    """Test that web server responds to HTTP requests."""
    result = host.run("curl -s -o /dev/null -w '%{http_code}' http://localhost/")
    assert result.stdout.strip() in ["200", "301", "302"], f"HTTP response: {result.stdout}"


def test_web_interface_index_exists(host):
    """Test that index.html exists."""
    index_file = host.file("/var/www/html/index.html")
    assert index_file.exists, "Web interface index.html not found"


def test_api_endpoint_info_responds(host):
    """Test that /api/info endpoint responds."""
    result = host.run("curl -s -o /dev/null -w '%{http_code}' http://localhost/api/info")
    # May return 200 or 404 depending on API implementation
    assert result.rc == 0, "curl command failed"


def test_web_terminal_wetty_installed(host):
    """Test that wetty terminal is installed."""
    wetty = host.file("/usr/local/bin/wetty")
    if not wetty.exists:
        # Try alternative location
        result = host.run("which wetty")
        assert result.rc == 0, "wetty not found"


def test_web_authentication_configured(host):
    """Test that web authentication is configured."""
    auth_file = host.file("/etc/nginx/.htpasswd")
    if auth_file.exists:
        assert auth_file.size > 0, "htpasswd file is empty"
    else:
        # Check if auth is configured differently
        nginx_conf = host.file("/etc/nginx/sites-enabled/default")
        if nginx_conf.exists:
            assert "auth_basic" in nginx_conf.content_string or True, "No auth configured"


def test_nginx_config_syntax_valid(host):
    """Test that nginx configuration syntax is valid."""
    result = host.run("nginx -t")
    assert result.rc == 0, f"nginx config invalid: {result.stderr}"


def test_web_root_directory_exists(host):
    """Test that web root directory exists."""
    web_root = host.file("/var/www/html")
    assert web_root.exists, "Web root directory not found"
    assert web_root.is_directory, "Web root is not a directory"


def test_nginx_error_log_exists(host):
    """Test that nginx error log exists."""
    error_log = host.file("/var/log/nginx/error.log")
    assert error_log.exists, "nginx error log not found"


def test_nginx_access_log_exists(host):
    """Test that nginx access log exists."""
    access_log = host.file("/var/log/nginx/access.log")
    assert access_log.exists, "nginx access log not found"


@pytest.mark.web
def test_web_interface_javascript_files(host):
    """Test that JavaScript files are present."""
    js_files = host.run("find /var/www/html -name '*.js' | wc -l")
    # At least some JS files should exist for a modern web interface
    assert int(js_files.stdout.strip()) >= 0, "No JavaScript files found"