-- Enable USB Audio devices
alsa_monitor.enabled = true

alsa_monitor.rules = {
  {
    matches = {
      {
        { "device.name", "matches", "alsa_card.*" },
      },
    },
    apply_properties = {
      ["api.alsa.use-acp"] = true,
      ["device.disabled"] = false,
    },
  },
  -- Specific rule for USB Audio HID
  {
    matches = {
      {
        { "alsa.card_name", "matches", "*USB Audio*" },
      },
    },
    apply_properties = {
      ["device.nick"] = "USB Audio 3.5mm",
      ["device.description"] = "USB Audio (3.5mm Jack)",
      ["priority.driver"] = 3000,
      ["priority.session"] = 3000,
      ["api.alsa.use-acp"] = true,
      ["device.disabled"] = false,
    },
  },
}