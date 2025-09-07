#!/bin/bash
# Load ALSA devices into PipeWire manually (when WirePlumber isn't available)

export PULSE_SERVER=unix:/run/user/999/pulse/native

echo "Loading ALSA devices into PipeWire..."

# Load USB Audio device if present
if aplay -l | grep -q "USB Audio"; then
    echo "Found USB Audio device, loading into PipeWire..."
    
    # Load playback device
    pactl load-module module-alsa-sink device=hw:1,0 sink_name=usb_audio_sink sink_properties="device.description='USB Audio Output'"
    
    # Load capture device  
    pactl load-module module-alsa-source device=hw:1,0 source_name=usb_audio_source source_properties="device.description='USB Audio Input'"
    
    echo "USB Audio devices loaded"
else
    echo "No USB Audio device found"
fi

# List loaded devices
echo "Available sinks:"
pactl list sinks short
echo "Available sources:"
pactl list sources short