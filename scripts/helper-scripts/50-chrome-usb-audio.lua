-- WirePlumber configuration to force Chrome to use USB Audio device
-- This file should be placed in /etc/wireplumber/main.lua.d/ or ~/.config/wireplumber/main.lua.d/

rule = {
  matches = {
    {
      -- Match Chrome/Chromium applications
      { "application.name", "matches", "*[Cc]hrome*" },
    },
    {
      -- Also match by process name
      { "application.process.binary", "matches", "*chrome*" },
    },
  },
  apply_properties = {
    -- Force Chrome to use the USB Audio device
    ["node.target"] = "alsa_output.usb-CSCTEK_USB_Audio_and_HID_A34004801402-00.analog-stereo",
    ["target.object"] = "alsa_output.usb-CSCTEK_USB_Audio_and_HID_A34004801402-00.analog-stereo",
  },
}

table.insert(alsa_monitor.rules, rule)

-- Also set up rules for input (microphone)
rule_input = {
  matches = {
    {
      { "application.name", "matches", "*[Cc]hrome*" },
    },
    {
      { "application.process.binary", "matches", "*chrome*" },
    },
  },
  apply_properties = {
    -- Force Chrome to use the USB Audio input
    ["node.target"] = "alsa_input.usb-CSCTEK_USB_Audio_and_HID_A34004801402-00.mono-fallback",
    ["target.object"] = "alsa_input.usb-CSCTEK_USB_Audio_and_HID_A34004801402-00.mono-fallback",
  },
}

table.insert(alsa_monitor.rules, rule_input)