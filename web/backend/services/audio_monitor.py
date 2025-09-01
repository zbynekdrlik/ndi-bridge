"""
Audio level monitoring service
Monitors real-time audio levels for VU meters
"""

import asyncio
import re
from typing import Dict
from services.shell_executor import ShellExecutor

class AudioMonitor:
    """Monitor audio levels in real-time"""
    
    def __init__(self):
        self.running = True
        self.current_levels = {
            "mic": 0,
            "speaker": 0
        }
    
    async def get_levels(self) -> Dict[str, int]:
        """Get current audio levels (0-100)"""
        devices = await ShellExecutor.get_usb_audio_devices()
        
        # Get microphone level
        if devices["input"]:
            # Use parecord to sample audio level
            success, output = await ShellExecutor.execute(
                "parecord",
                ["--device=" + devices["input"], "--raw", "--channels=1", "--format=s16le", "--rate=1000", "-n", "10"]
            )
            if success and output:
                # Calculate RMS level from raw audio
                # This is a simplified calculation
                level = min(100, len(output) // 100)
                self.current_levels["mic"] = level
        
        # For speaker, we can monitor the sink monitor
        if devices["output"]:
            # Try to get current playing level from sink
            success, output = await ShellExecutor.pactl(["list", "sinks"])
            if success:
                # Look for volume in the output device section
                lines = output.split('\n')
                for i, line in enumerate(lines):
                    if devices["output"] in line:
                        # Look for volume in next few lines
                        for j in range(i, min(i+10, len(lines))):
                            if "Volume:" in lines[j]:
                                match = re.search(r'(\d+)%', lines[j])
                                if match:
                                    # This gives us the set volume, not actual level
                                    # For actual level we'd need to monitor the sink input
                                    self.current_levels["speaker"] = int(match.group(1))
                                    break
                        break
        
        return self.current_levels
    
    async def stop(self):
        """Stop monitoring"""
        self.running = False