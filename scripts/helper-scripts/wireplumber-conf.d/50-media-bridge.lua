-- Media Bridge WirePlumber Configuration
-- Device policies and routing rules

-- Enable USB audio devices (CSCTEK for intercom)
alsa_monitor.enabled = true

alsa_monitor.rules = {
  -- Rule for USB Audio devices
  {
    matches = {
      {
        { "node.name", "matches", "alsa_*.usb-*" },
      },
    },
    apply_properties = {
      ["node.nick"] = "USB Audio Device",
      ["priority.driver"] = 1000,
      ["priority.session"] = 1000,
      ["node.pause-on-idle"] = false,
    },
  },
  
  -- Specific rule for CSCTEK USB Audio HID
  {
    matches = {
      {
        { "alsa.card_name", "matches", "*CSCTEK*USB*Audio*" },
      },
    },
    apply_properties = {
      ["node.nick"] = "CSCTEK USB Audio",
      ["node.description"] = "Intercom USB Audio (3.5mm)",
      ["priority.driver"] = 1500,
      ["priority.session"] = 1500,
      ["node.pause-on-idle"] = false,
      ["api.alsa.use-acp"] = false,  -- Direct ALSA access for lower latency
      ["api.alsa.period-size"] = 256,
      ["api.alsa.headroom"] = 128,
    },
  },
  
  -- Rule for HDMI audio (for ndi-display)
  {
    matches = {
      {
        { "node.name", "matches", "alsa_*.hdmi-*" },
      },
    },
    apply_properties = {
      ["node.nick"] = "HDMI Audio",
      ["priority.driver"] = 900,
      ["priority.session"] = 900,
      ["node.pause-on-idle"] = false,
    },
  },
}

-- Default device policy
default_policy = {}

default_policy.enabled = true

default_policy.properties = {
  -- Use virtual devices as defaults for applications
  ["default.configured.audio.sink"] = { ["name"] = "intercom-speaker" },
  ["default.configured.audio.source"] = { ["name"] = "intercom-microphone" },
}

-- Linking policy to connect virtual devices to hardware
linking_policy = {}

linking_policy.enabled = true

-- These rules will be applied by the audio manager script
-- to ensure proper USB device detection before linking
linking_policy.rules = {
  -- Link virtual speaker to USB output
  {
    matches = {
      {
        { "node.name", "equals", "intercom-speaker" },
      },
    },
    actions = {
      ["link-to"] = "alsa_output.*CSCTEK*",
    },
  },
  
  -- Link USB input to virtual microphone
  {
    matches = {
      {
        { "node.name", "matches", "alsa_input.*CSCTEK*" },
      },
    },
    actions = {
      ["link-to"] = "intercom-microphone",
    },
  },
}

-- Low latency settings for the session
settings = {}

settings["clock.rate"] = 48000
settings["clock.quantum"] = 256
settings["clock.min-quantum"] = 128
settings["clock.max-quantum"] = 512