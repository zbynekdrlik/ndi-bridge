"""
Pydantic models for API schemas
"""

from pydantic import BaseModel, Field
from typing import Optional, Dict

class AudioDevice(BaseModel):
    """Audio device information"""
    input: Optional[str] = Field(None, description="Input device name")
    output: Optional[str] = Field(None, description="Output device name")

class IntercomState(BaseModel):
    """Complete intercom state"""
    mic_muted: bool = Field(False, description="Microphone mute state")
    speaker_muted: bool = Field(False, description="Speaker mute state")
    mic_volume: int = Field(75, ge=0, le=100, description="Microphone volume (0-100)")
    speaker_volume: int = Field(75, ge=0, le=100, description="Speaker volume (0-100)")
    devices: AudioDevice = Field(..., description="Audio devices")

class AudioLevels(BaseModel):
    """Real-time audio levels for VU meters"""
    mic: int = Field(0, ge=0, le=100, description="Microphone level (0-100)")
    speaker: int = Field(0, ge=0, le=100, description="Speaker level (0-100)")

class WebSocketMessage(BaseModel):
    """WebSocket message format"""
    type: str = Field(..., description="Message type")
    data: Dict = Field(..., description="Message data")