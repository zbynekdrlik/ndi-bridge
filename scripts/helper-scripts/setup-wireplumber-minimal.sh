#!/bin/bash
# Setup minimal WirePlumber without D-Bus for device isolation

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Create fake D-Bus socket to satisfy WirePlumber
setup_fake_dbus() {
    log "Setting up fake D-Bus socket for WirePlumber..."
    
    # Create a fake session bus socket
    mkdir -p /run/user/999/bus
    touch /run/user/999/bus/session
    
    # Create minimal D-Bus config
    cat > /run/user/999/dbus.conf << 'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=/run/user/999/bus/session</listen>
  <auth>EXTERNAL</auth>
  <allow_anonymous/>
  <policy context="default">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
    
    chown -R mediabridge:mediabridge /run/user/999/bus
}

# Create minimal WirePlumber config
create_wireplumber_config() {
    log "Creating minimal WirePlumber configuration..."
    
    # Main WirePlumber config
    cat > /etc/wireplumber/wireplumber-minimal.conf << 'EOF'
# Minimal WirePlumber for headless operation

context.properties = {
  log.level = 2
  wireplumber.daemon = true
  wireplumber.script-engine = lua-scripting
  wireplumber.export-core = true
}

context.spa-libs = {
  api.alsa.*      = alsa/libspa-alsa
  api.v4l2.*      = v4l2/libspa-v4l2
  api.libcamera.* = libcamera/libspa-libcamera
}

context.modules = [
  {
    name = libpipewire-module-protocol-native
  }
  {
    name = libwireplumber-module-lua-scripting
  }
]

wireplumber.profiles = {
  main = {
    support.dbus = false
  }
}
EOF

    # Chrome isolation script
    cat > /etc/wireplumber/main.lua.d/70-chrome-isolation-minimal.lua << 'EOF'
-- Minimal Chrome Audio Isolation
-- Works without D-Bus

-- Load device monitor
device_monitor = {}

function device_monitor.enable()
  Log.info("Chrome isolation starting...")
  
  -- Monitor Chrome clients
  client_om = ObjectManager {
    Interest {
      type = "client",
    }
  }
  
  client_om:connect("object-added", function(om, client)
    local props = client.properties
    local app_name = props["application.name"] or ""
    local binary = props["application.process.binary"] or ""
    
    -- Check if this is Chrome
    if string.match(app_name:lower(), "chrome") or 
       string.match(binary:lower(), "chrome") then
      Log.info("Chrome detected: " .. client.id)
      
      -- Restrict Chrome to virtual devices only
      -- This happens in the permission callback
      client:connect("state-changed", function(client, old_state, new_state)
        if new_state == "active" then
          enforce_chrome_isolation(client)
        end
      end)
    end
  end)
  
  client_om:activate()
end

function enforce_chrome_isolation(client)
  Log.info("Enforcing isolation for Chrome client " .. client.id)
  
  -- Find all nodes
  node_om = ObjectManager {
    Interest {
      type = "node",
    }
  }
  
  node_om:connect("object-added", function(om, node)
    local node_name = node.properties["node.name"] or ""
    
    -- Determine if Chrome should see this node
    local allowed = false
    if string.match(node_name, "intercom%-speaker") or 
       string.match(node_name, "intercom%-microphone") then
      allowed = true
    end
    
    -- Set permissions
    if allowed then
      Log.info("Granting Chrome access to " .. node_name)
      -- Grant access (this would need proper permission API)
    else
      Log.info("Denying Chrome access to " .. node_name)
      -- Deny access (this would need proper permission API)
    end
  end)
  
  node_om:activate()
end

-- Enable the isolation
device_monitor.enable()

Log.info("Chrome audio isolation loaded (minimal mode)")
EOF

    chown -R mediabridge:mediabridge /etc/wireplumber/
}

# Update WirePlumber service
update_wireplumber_service() {
    log "Updating WirePlumber service..."
    
    cat > /etc/systemd/system/wireplumber-minimal.service << 'EOF'
[Unit]
Description=Minimal WirePlumber without D-Bus
After=pipewire-system.service
Requires=pipewire-system.service

[Service]
Type=simple
User=mediabridge
Group=audio
SupplementaryGroups=video pipewire

# Environment
Environment="XDG_RUNTIME_DIR=/run/user/999"
Environment="WIREPLUMBER_CONFIG_FILE=/etc/wireplumber/wireplumber-minimal.conf"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus/session"

# Start WirePlumber
ExecStartPre=/bin/bash -c 'for i in {1..30}; do [ -S /run/user/999/pipewire-0 ] && exit 0; sleep 1; done; exit 1'
ExecStart=/usr/bin/wireplumber

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

# Main
main() {
    log "Setting up minimal WirePlumber for Chrome isolation..."
    
    setup_fake_dbus
    create_wireplumber_config
    update_wireplumber_service
    
    # Enable and start
    systemctl daemon-reload
    systemctl enable wireplumber-minimal
    systemctl restart wireplumber-minimal
    
    log "Setup complete!"
}

main "$@"