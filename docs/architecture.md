# Media Bridge Architecture

## Overview

Media Bridge is designed as a modular, cross-platform application with platform-specific implementations for optimal performance.

## Core Components

### 1. Capture Layer
Responsible for acquiring video/audio from HDMI sources.

#### Windows
- **Media Foundation**: Standard USB/HDMI capture devices
- **DeckLink SDK**: Professional Blackmagic capture cards

#### Linux
- **V4L2**: Video4Linux2 for standard devices
- **Direct DMA**: For minimal latency on supported hardware

### 2. Processing Layer
- Frame format conversion
- Color space transformation
- Audio resampling if needed
- Minimal buffering for low latency

### 3. NDI Output Layer
- NDI SDK integration
- Network stream management
- Metadata handling

## Data Flow

```
HDMI Input → Capture Device → Frame Buffer → Format Conversion → NDI Encoder → Network Output
```

## Threading Model

- **Capture Thread**: Dedicated thread for each capture device
- **Processing Thread**: Handles format conversion and buffering
- **NDI Thread**: Manages network transmission

## Performance Considerations

1. **Zero-Copy Operations**: Where possible, use direct memory access
2. **Lock-Free Queues**: For inter-thread communication
3. **GPU Acceleration**: Optional for format conversion
4. **Minimal Buffering**: Single frame buffer to reduce latency
