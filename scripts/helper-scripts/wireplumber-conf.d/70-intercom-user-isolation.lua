-- WirePlumber Configuration for Chrome Audio Isolation
-- This script enforces strict audio device access for Chrome browser

rule = {
  matches = {
    {
      -- Match Chrome clients by application name
      { "application.name", "matches", "*[Cc]hrome*" },
    },
    {
      -- Also match by process binary
      { "application.process.binary", "matches", "*chrome*" },
    },
  },
  apply_properties = {
    -- Mark as restricted access
    ["pipewire.access"] = "restricted",
    ["media.role"] = "intercom",
    
    -- Start with no permissions
    ["default.permissions"] = "",
  },
}

table.insert(access.rules, rule)

-- Create a monitor to enforce permissions
access_monitor = {}

access_monitor.client_added = function(client)
  local app_name = client.properties["application.name"] or ""
  local proc_binary = client.properties["application.process.binary"] or ""
  
  if string.match(app_name:lower(), "chrome") or string.match(proc_binary:lower(), "chrome") then
    Log.info("Chrome client detected: " .. client.id)
    
    -- Find virtual devices
    local om = ObjectManager {
      Interest {
        type = "node",
        Constraint { "node.name", "matches", "intercom-*" }
      }
    }
    
    om:connect("object-added", function(_, node)
      -- Grant access to virtual devices
      client:update_permissions {
        [node.id] = "rwx",
      }
      Log.info("Granted Chrome access to virtual device: " .. node.properties["node.name"])
    end)
    
    -- Find hardware devices to deny
    local hw_om = ObjectManager {
      Interest {
        type = "node",
        Constraint { "node.name", "matches", "alsa_*" }
      }
    }
    
    hw_om:connect("object-added", function(_, node)
      -- Deny access to hardware devices
      client:update_permissions {
        [node.id] = "",
      }
      Log.info("Denied Chrome access to hardware device: " .. node.properties["node.name"])
    end)
    
    om:activate()
    hw_om:activate()
  end
end

-- Monitor for new clients
client_om = ObjectManager {
  Interest {
    type = "client",
  }
}

client_om:connect("object-added", access_monitor.client_added)
client_om:activate()

Log.info("Intercom user isolation rules loaded")