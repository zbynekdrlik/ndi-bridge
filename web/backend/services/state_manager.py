"""
State management service
Manages intercom state and configuration
"""

import json
import os
from typing import Dict, Any
from services.shell_executor import ShellExecutor

class StateManager:
    """Manage intercom state"""
    
    def __init__(self):
        self.runtime_state_file = "/var/run/ndi-bridge/intercom.state"
        self.config_file = "/etc/ndi-bridge/intercom.conf"
        self.state = {
            "mic_muted": False,
            "speaker_volume": 75,
            "mic_volume": 75,
            "speaker_muted": False,
            "devices": {
                "input": None,
                "output": None
            },
            "monitor_enabled": False,
            "monitor_volume": 50
        }
        
    async def get_state(self) -> Dict[str, Any]:
        """Get current state from audio system"""
        # Get USB audio devices
        devices = await ShellExecutor.get_usb_audio_devices()
        self.state["devices"] = devices
        
        # Get volume levels
        if devices["output"]:
            success, output = await ShellExecutor.pactl(["get-sink-volume", devices["output"]])
            if success:
                # Parse volume percentage
                import re
                match = re.search(r'(\d+)%', output)
                if match:
                    self.state["speaker_volume"] = int(match.group(1))
            
            # Get mute state
            success, output = await ShellExecutor.pactl(["get-sink-mute", devices["output"]])
            if success:
                self.state["speaker_muted"] = "yes" in output
        
        if devices["input"]:
            success, output = await ShellExecutor.pactl(["get-source-volume", devices["input"]])
            if success:
                import re
                match = re.search(r'(\d+)%', output)
                if match:
                    self.state["mic_volume"] = int(match.group(1))
            
            # Get mute state
            success, output = await ShellExecutor.pactl(["get-source-mute", devices["input"]])
            if success:
                self.state["mic_muted"] = "yes" in output
        
        # Get monitor status
        success, output = await ShellExecutor.run_command(
            "/usr/local/bin/ndi-bridge-intercom-monitor", ["status"]
        )
        if success:
            try:
                monitor_status = json.loads(output)
                self.state["monitor_enabled"] = monitor_status.get("enabled", False)
                self.state["monitor_volume"] = monitor_status.get("volume", 50)
            except json.JSONDecodeError:
                pass
        
        return self.state
    
    async def set_mic_mute(self, muted: bool) -> bool:
        """Set microphone mute state - affects both VDO and monitoring"""
        devices = await ShellExecutor.get_usb_audio_devices()
        if not devices["input"]:
            return False
        
        mute_value = "1" if muted else "0"
        success, _ = await ShellExecutor.pactl(["set-source-mute", devices["input"], mute_value])
        
        if success:
            self.state["mic_muted"] = muted
            
            # When mic is muted, also mute the monitor loopback
            # When unmuted, restore monitor to previous volume
            if muted:
                # Mute monitor by setting volume to 0
                await ShellExecutor.run_command(
                    "/usr/local/bin/ndi-bridge-intercom-monitor",
                    ["volume", "0"]
                )
            else:
                # Restore monitor volume
                monitor_vol = self.state.get("monitor_volume", 50)
                await ShellExecutor.run_command(
                    "/usr/local/bin/ndi-bridge-intercom-monitor",
                    ["volume", str(monitor_vol)]
                )
            
            await self.save_runtime_state()
        
        return success
    
    async def set_speaker_volume(self, volume: int) -> bool:
        """Set speaker volume (0-100)"""
        devices = await ShellExecutor.get_usb_audio_devices()
        if not devices["output"]:
            return False
        
        volume = max(0, min(100, volume))  # Clamp to 0-100
        success, _ = await ShellExecutor.pactl(["set-sink-volume", devices["output"], f"{volume}%"])
        
        if success:
            self.state["speaker_volume"] = volume
            await self.save_runtime_state()
        
        return success
    
    async def set_mic_volume(self, volume: int) -> bool:
        """Set microphone volume (0-100)"""
        devices = await ShellExecutor.get_usb_audio_devices()
        if not devices["input"]:
            return False
        
        volume = max(0, min(100, volume))  # Clamp to 0-100
        success, _ = await ShellExecutor.pactl(["set-source-volume", devices["input"], f"{volume}%"])
        
        if success:
            self.state["mic_volume"] = volume
            await self.save_runtime_state()
        
        return success
    
    async def set_speaker_mute(self, muted: bool) -> bool:
        """Set speaker mute state"""
        devices = await ShellExecutor.get_usb_audio_devices()
        if not devices["output"]:
            return False
        
        mute_value = "1" if muted else "0"
        success, _ = await ShellExecutor.pactl(["set-sink-mute", devices["output"], mute_value])
        
        if success:
            self.state["speaker_muted"] = muted
            await self.save_runtime_state()
        
        return success
    
    async def save_runtime_state(self):
        """Save state to runtime file (tmpfs)"""
        try:
            os.makedirs(os.path.dirname(self.runtime_state_file), exist_ok=True)
            with open(self.runtime_state_file, 'w') as f:
                json.dump(self.state, f, indent=2)
        except Exception as e:
            print(f"Failed to save runtime state: {e}")
    
    async def save_as_default(self) -> bool:
        """Save current settings as default configuration"""
        try:
            # Create config directory if it doesn't exist
            os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
            
            # Save only the settings we want to persist
            config = {
                "speaker_volume": self.state["speaker_volume"],
                "mic_volume": self.state["mic_volume"],
                "mic_muted": self.state["mic_muted"],
                "speaker_muted": self.state["speaker_muted"],
                "monitor_enabled": self.state.get("monitor_enabled", False),
                "monitor_volume": self.state.get("monitor_volume", 50)
            }
            
            # Write to temporary file first (atomic write)
            temp_file = f"{self.config_file}.tmp"
            with open(temp_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            # Atomic move
            os.rename(temp_file, self.config_file)
            
            return True
        except Exception as e:
            print(f"Failed to save default config: {e}")
            return False
    
    async def load_defaults(self) -> bool:
        """Load default configuration if it exists"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                
                # Apply loaded settings
                if "speaker_volume" in config:
                    await self.set_speaker_volume(config["speaker_volume"])
                if "mic_volume" in config:
                    await self.set_mic_volume(config["mic_volume"])
                if "mic_muted" in config:
                    await self.set_mic_mute(config["mic_muted"])
                if "speaker_muted" in config:
                    await self.set_speaker_mute(config["speaker_muted"])
                if "monitor_enabled" in config:
                    await self.set_monitor_state(config["monitor_enabled"], 
                                                 config.get("monitor_volume", 50))
                
                return True
        except Exception as e:
            print(f"Failed to load defaults: {e}")
        
        return False
    
    async def set_monitor_state(self, enabled: bool, volume: int = 50) -> bool:
        """Enable/disable self-monitoring"""
        command = "enable" if enabled else "disable"
        args = [command]
        if enabled:
            args.append(str(volume))
        
        success, _ = await ShellExecutor.run_command(
            "/usr/local/bin/ndi-bridge-intercom-monitor", args
        )
        
        if success:
            self.state["monitor_enabled"] = enabled
            self.state["monitor_volume"] = volume
            await self.save_runtime_state()
        
        return success
    
    async def set_monitor_volume(self, volume: int) -> bool:
        """Set monitor volume (0-100)"""
        success, _ = await ShellExecutor.run_command(
            "/usr/local/bin/ndi-bridge-intercom-monitor", 
            ["volume", str(volume)]
        )
        
        if success:
            self.state["monitor_volume"] = volume
            await self.save_runtime_state()
        
        return success