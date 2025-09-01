#!/usr/bin/env python3
"""
NDI Bridge Intercom Control API
FastAPI backend for web-based intercom control
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import asyncio
import json
import os
from typing import Set, Dict, Any

from api.intercom import router as intercom_router
from services.state_manager import StateManager
from services.audio_monitor import AudioMonitor

# Create FastAPI app
app = FastAPI(
    title="NDI Bridge Intercom API",
    version="2.0.0",
    description="Web control interface for NDI Bridge intercom system"
)

# CORS middleware for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global state manager
state_manager = StateManager()
audio_monitor = AudioMonitor()

# WebSocket connections
websocket_clients: Set[WebSocket] = set()

# Include API routers
app.include_router(intercom_router, prefix="/api/intercom")

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    # Start audio monitoring task
    asyncio.create_task(audio_monitor_task())
    print("NDI Bridge Intercom API started on port 8000")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    await audio_monitor.stop()
    # Close all WebSocket connections
    for ws in websocket_clients:
        await ws.close()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    websocket_clients.add(websocket)
    
    try:
        # Send initial state
        state = await state_manager.get_state()
        await websocket.send_json(state)
        
        # Keep connection alive and handle messages
        while True:
            # Wait for messages from client
            data = await websocket.receive_json()
            # Handle client commands if needed
            if data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        websocket_clients.remove(websocket)
    except Exception as e:
        print(f"WebSocket error: {e}")
        if websocket in websocket_clients:
            websocket_clients.remove(websocket)

async def audio_monitor_task():
    """Background task to monitor audio levels"""
    while True:
        try:
            # Get audio levels
            levels = await audio_monitor.get_levels()
            
            # Broadcast to all connected clients
            for ws in websocket_clients:
                try:
                    await ws.send_json({
                        "type": "audio_levels",
                        "data": levels
                    })
                except:
                    # Client disconnected
                    pass
            
            # Update 10 times per second
            await asyncio.sleep(0.1)
        except Exception as e:
            print(f"Audio monitor error: {e}")
            await asyncio.sleep(1)

async def broadcast_state_update(update_type: str, data: Dict[str, Any]):
    """Broadcast state updates to all WebSocket clients"""
    message = {
        "type": update_type,
        "data": data
    }
    
    for ws in list(websocket_clients):
        try:
            await ws.send_json(message)
        except:
            # Remove disconnected clients
            websocket_clients.discard(ws)

# Serve static files (Vue frontend)
app.mount("/", StaticFiles(directory="../frontend", html=True), name="static")

# Export broadcast function for use in other modules
app.broadcast_state_update = broadcast_state_update

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)