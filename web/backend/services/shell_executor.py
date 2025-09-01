"""
Shell command executor service
Wraps shell commands for audio control
"""

import asyncio
import subprocess
from typing import List, Tuple, Optional

class ShellExecutor:
    """Execute shell commands safely"""
    
    @staticmethod
    async def execute(command: str, args: List[str] = None) -> Tuple[bool, str]:
        """
        Execute a shell command asynchronously
        
        Returns:
            Tuple of (success: bool, output: str)
        """
        try:
            # Build command
            cmd = [command]
            if args:
                cmd.extend(args)
            
            # Execute
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={
                    "XDG_RUNTIME_DIR": "/run/user/0",
                    "PULSE_RUNTIME_PATH": "/run/user/0/pulse"
                }
            )
            
            stdout, stderr = await process.communicate()
            
            if process.returncode == 0:
                return True, stdout.decode().strip()
            else:
                return False, stderr.decode().strip()
                
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    async def pactl(args: List[str]) -> Tuple[bool, str]:
        """Execute pactl command"""
        return await ShellExecutor.execute("pactl", args)
    
    @staticmethod
    async def get_usb_audio_devices() -> dict:
        """Get USB audio input and output devices"""
        devices = {
            "input": None,
            "output": None
        }
        
        # Get sinks (output devices)
        success, output = await ShellExecutor.pactl(["list", "sinks", "short"])
        if success:
            for line in output.split('\n'):
                if 'usb' in line.lower() or 'USB' in line:
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        devices["output"] = parts[1]
                        break
        
        # Get sources (input devices)
        success, output = await ShellExecutor.pactl(["list", "sources", "short"])
        if success:
            for line in output.split('\n'):
                if ('usb' in line.lower() or 'USB' in line) and 'monitor' not in line:
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        devices["input"] = parts[1]
                        break
        
        return devices