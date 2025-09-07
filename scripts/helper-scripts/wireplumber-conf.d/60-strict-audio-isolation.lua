-- Media Bridge Strict Audio Isolation Configuration
-- Implements permission-based device filtering for security
-- Each application ONLY sees its authorized audio devices

-- Enable access control
access_control = {}
access_control.enabled = true

-- Define strict access rules for each application
access_control.rules = {
  -- Chrome/VDO.Ninja - ONLY sees virtual intercom devices
  {
    matches = {
      {
        { "application.process.binary", "equals", "chrome" },
      },
      {
        { "application.process.binary", "equals", "google-chrome" },
      },
      {
        { "application.process.binary", "equals", "chromium" },
      },
    },
    actions = {
      update_props = {
        ["pipewire.access"] = "restricted",
        ["pipewire.access.portal"] = false,
        ["default.permissions"] = "",  -- Start with NO permissions
        ["media.role"] = "intercom",
        ["node.access"] = "restricted",
      },
    },
  },
  
  -- ndi-display - ONLY sees HDMI outputs
  {
    matches = {
      {
        { "application.name", "equals", "ndi-display" },
      },
      {
        { "application.process.binary", "matches", "*ndi-display*" },
      },
    },
    actions = {
      update_props = {
        ["pipewire.access"] = "restricted",
        ["default.permissions"] = "",  -- Start with NO permissions
        ["media.role"] = "hdmi-output",
        ["node.access"] = "restricted",
      },
    },
  },
  
  -- System services (PipeWire, WirePlumber) - need full access
  {
    matches = {
      {
        { "application.process.binary", "equals", "pipewire" },
      },
      {
        { "application.process.binary", "equals", "wireplumber" },
      },
      {
        { "application.process.binary", "equals", "pw-cli" },
      },
      {
        { "application.process.binary", "equals", "pw-link" },
      },
    },
    actions = {
      update_props = {
        ["pipewire.access"] = "unrestricted",
        ["default.permissions"] = "all",
      },
    },
  },
  
  -- Default rule: DENY ALL for unknown applications
  {
    matches = {
      {
        -- Match everything not matched above
        { "application.name", "matches", "*" },
      },
    },
    actions = {
      update_props = {
        ["pipewire.access"] = "restricted",
        ["default.permissions"] = "",  -- NO permissions by default
        ["node.access"] = "denied",
      },
    },
  },
}

-- Device visibility rules based on media.role
device_access = {}
device_access.enabled = true

device_access.rules = {
  -- Chrome with intercom role can ONLY access virtual devices
  {
    matches = {
      {
        { "media.role", "equals", "intercom" },
      },
    },
    allowed_devices = {
      "intercom-speaker",
      "intercom-microphone",
      "intercom-speaker.monitor",  -- Monitor is OK
    },
    denied_patterns = {
      "hdmi", "HDMI",
      "usb", "USB",
      "CSCTEK",
      "alsa_output.pci",
      "alsa_input.usb",
    },
  },
  
  -- ndi-display can ONLY access HDMI outputs
  {
    matches = {
      {
        { "media.role", "equals", "hdmi-output" },
      },
    },
    allowed_patterns = {
      "hdmi", "HDMI",
      "alsa_output.pci.*hdmi",
    },
    denied_devices = {
      "intercom-speaker",
      "intercom-microphone",
      "CSCTEK",
      "USB",
    },
  },
}

-- Session policy to enforce permissions
session_policy = {}
session_policy.enabled = true

session_policy.actions = {
  -- When a client connects, check its role and set permissions
  ["client.connected"] = function(client)
    local role = client.properties["media.role"]
    local app_name = client.properties["application.name"]
    local binary = client.properties["application.process.binary"]
    
    -- Log the connection
    Log.info("Client connected: " .. (app_name or "unknown") .. 
             " (" .. (binary or "unknown") .. ") with role: " .. (role or "none"))
    
    -- Apply permissions based on role
    if role == "intercom" then
      -- Chrome gets access ONLY to virtual devices
      Log.info("Granting Chrome access to virtual intercom devices only")
      client:set_permissions({
        ["intercom-speaker"] = "rwx",
        ["intercom-microphone"] = "rwx",
      })
    elseif role == "hdmi-output" then
      -- ndi-display gets access ONLY to HDMI
      Log.info("Granting ndi-display access to HDMI outputs only")
      -- Find HDMI devices and grant access
      for device in devices:iterate() do
        if string.match(device.properties["node.name"], "hdmi") then
          client:set_permission(device.id, "rwx")
        end
      end
    else
      -- Unknown role - no access
      Log.warning("Denying access to client with unknown role: " .. (role or "none"))
      client:set_permissions({})  -- Empty permissions = no access
    end
  end,
}

-- Low latency settings remain the same
settings = {}
settings["clock.rate"] = 48000
settings["clock.quantum"] = 256
settings["clock.min-quantum"] = 128
settings["clock.max-quantum"] = 512

-- Logging for debugging
settings["log.level"] = "info"
settings["log.rules"] = {
  {
    matches = {
      {
        { "category", "equals", "access" },
      },
    },
    actions = {
      ["log.level"] = "debug",
    },
  },
}