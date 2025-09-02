"""
Intercom API endpoints
Handles all intercom control operations
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from services.state_manager import StateManager
from services.shell_executor import ShellExecutor

router = APIRouter()
state_manager = StateManager()

# Pydantic models for request/response
class MuteRequest(BaseModel):
    muted: bool

class VolumeRequest(BaseModel):
    volume: int  # 0-100

class StateResponse(BaseModel):
    mic_muted: bool
    speaker_muted: bool
    mic_volume: int
    speaker_volume: int
    devices: dict
    monitor_enabled: bool = False
    monitor_volume: int = 50

@router.get("/state", response_model=StateResponse)
async def get_state():
    """Get current intercom state"""
    state = await state_manager.get_state()
    return state

@router.post("/mic/mute")
async def set_mic_mute(request: MuteRequest):
    """Set microphone mute state - PRIMARY CONTROL"""
    success = await state_manager.set_mic_mute(request.muted)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set mic mute")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("mic_mute", {"muted": request.muted})
    
    return {"status": "success", "muted": request.muted}

@router.post("/mic/toggle")
async def toggle_mic_mute():
    """Toggle microphone mute state - For quick access"""
    current_state = await state_manager.get_state()
    new_muted = not current_state["mic_muted"]
    
    success = await state_manager.set_mic_mute(new_muted)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to toggle mic mute")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("mic_mute", {"muted": new_muted})
    
    return {"status": "success", "muted": new_muted}

@router.post("/speaker/volume")
async def set_speaker_volume(request: VolumeRequest):
    """Set speaker/headphone volume"""
    success = await state_manager.set_speaker_volume(request.volume)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set speaker volume")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("speaker_volume", {"volume": request.volume})
    
    return {"status": "success", "volume": request.volume}

@router.post("/mic/volume")
async def set_mic_volume(request: VolumeRequest):
    """Set microphone volume"""
    success = await state_manager.set_mic_volume(request.volume)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set mic volume")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("mic_volume", {"volume": request.volume})
    
    return {"status": "success", "volume": request.volume}

@router.post("/speaker/mute")
async def set_speaker_mute(request: MuteRequest):
    """Set speaker mute state"""
    success = await state_manager.set_speaker_mute(request.muted)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set speaker mute")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("speaker_mute", {"muted": request.muted})
    
    return {"status": "success", "muted": request.muted}

@router.post("/save-defaults")
async def save_as_default():
    """Save current settings as default configuration"""
    success = await state_manager.save_as_default()
    if not success:
        raise HTTPException(status_code=500, detail="Failed to save default configuration")
    
    return {"status": "success", "message": "Settings saved as default"}

@router.post("/load-defaults")
async def load_defaults():
    """Load default configuration"""
    success = await state_manager.load_defaults()
    if not success:
        raise HTTPException(status_code=404, detail="No default configuration found")
    
    # Broadcast full state update
    state = await state_manager.get_state()
    from main import app
    await app.broadcast_state_update("full_state", state)
    
    return {"status": "success", "message": "Default settings loaded"}

@router.get("/devices")
async def get_audio_devices():
    """Get available audio devices"""
    devices = await ShellExecutor.get_usb_audio_devices()
    return devices

# Monitoring endpoints
class MonitorRequest(BaseModel):
    enabled: bool
    volume: Optional[int] = 50  # 0-100

@router.post("/monitor")
async def set_monitor_state(request: MonitorRequest):
    """Enable/disable self-monitoring with volume control"""
    success = await state_manager.set_monitor_state(request.enabled, request.volume)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set monitor state")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("monitor", {
        "enabled": request.enabled,
        "volume": request.volume
    })
    
    return {"status": "success", "enabled": request.enabled, "volume": request.volume}

@router.post("/monitor/volume")
async def set_monitor_volume(request: VolumeRequest):
    """Set monitor volume (0-100)"""
    success = await state_manager.set_monitor_volume(request.volume)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set monitor volume")
    
    # Broadcast update via WebSocket
    from main import app
    await app.broadcast_state_update("monitor_volume", {"volume": request.volume})
    
    return {"status": "success", "volume": request.volume}