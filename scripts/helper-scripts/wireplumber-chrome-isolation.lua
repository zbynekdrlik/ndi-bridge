-- WirePlumber Chrome Isolation Rules
-- Restricts Chrome to ONLY see virtual intercom devices

rule = {
  matches = {
    {
      -- Match Chrome processes
      { "application.name", "matches", "*[Cc]hrome*" },
    },
  },
  apply_properties = {
    -- Force Chrome to only use virtual devices
    ["media.role"] = "communication",
    ["node.autoconnect"] = false,
    ["node.exclusive"] = false,
  },
}

table.insert(alsa_monitor.rules, rule)

-- Device access control for Chrome
device_access_rule = {
  matches = {
    {
      { "application.name", "matches", "*[Cc]hrome*" },
    },
  },
  apply_properties = {
    -- Hide hardware devices from Chrome
    ["device.access"] = "restricted",
    ["node.hidden"] = true,
  },
}

-- Virtual device priority for Chrome
virtual_device_rule = {
  matches = {
    {
      { "node.name", "equals", "intercom-speaker" },
    },
    {
      { "node.name", "equals", "intercom-microphone" },
    },
  },
  apply_properties = {
    -- Make virtual devices visible and high priority
    ["priority.session"] = 2000,
    ["priority.driver"] = 2000,
    ["node.hidden"] = false,
    ["device.access"] = "allowed",
  },
}

-- Auto-connect Chrome to virtual devices
chrome_routing_rule = {
  matches = {
    {
      { "application.name", "matches", "*[Cc]hrome*" },
      { "media.class", "equals", "Stream/Output/Audio" },
    },
  },
  apply_properties = {
    ["target.object"] = "intercom-speaker",
    ["node.autoconnect"] = true,
  },
}

chrome_input_routing_rule = {
  matches = {
    {
      { "application.name", "matches", "*[Cc]hrome*" },
      { "media.class", "equals", "Stream/Input/Audio" },
    },
  },
  apply_properties = {
    ["target.object"] = "intercom-microphone",
    ["node.autoconnect"] = true,
  },
}

-- Export rules for WirePlumber to use
if alsa_monitor then
  table.insert(alsa_monitor.rules, device_access_rule)
  table.insert(alsa_monitor.rules, virtual_device_rule)
  table.insert(alsa_monitor.rules, chrome_routing_rule)
  table.insert(alsa_monitor.rules, chrome_input_routing_rule)
end

-- Log configuration loaded
Log.info("Chrome isolation rules loaded - Chrome will only see virtual intercom devices")