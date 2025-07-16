// DeckLinkCaptureDevice.h
#pragma once

#include "ICaptureDevice.h"
#include "IFormatConverter.h"
#include <memory>
#include <atomic>
#include <chrono>
#include <functional>
#include <atlbase.h>
#include <vector>

// Forward declarations for DeckLink SDK
struct IDeckLink;
struct IDeckLinkInput;
struct IDeckLinkDisplayMode;
struct IDeckLinkVideoInputFrame;
struct IDeckLinkAudioInputPacket;
struct IDeckLinkInputCallback;
struct IDeckLinkProfileAttributes;

// Include the actual DeckLink types instead of forward declaring enums
#ifdef HAS_DECKLINK
#include "DeckLinkAPI_h.h"
#else
// Fallback typedefs if DeckLink is not available
typedef uint32_t BMDPixelFormat;
typedef uint32_t BMDVideoInputFlags;
typedef uint32_t BMDDisplayMode;
typedef uint32_t BMDVideoInputFormatChangedEvents;
typedef uint32_t BMDDetectedVideoInputFormatFlags;
typedef int64_t BMDTimeValue;
typedef int64_t BMDTimeScale;
#endif

// Forward declarations for refactored components
class DeckLinkCaptureCallback;
class DeckLinkFrameQueue;
class DeckLinkStatistics;
class DeckLinkFormatManager;
class DeckLinkDeviceInitializer;

/**
 * @brief DeckLink capture device implementation
 * 
 * Refactored in v1.2.0 to use separate components for better maintainability:
 * - DeckLinkCaptureCallback: Handles IDeckLinkInputCallback implementation
 * - DeckLinkFrameQueue: Manages thread-safe frame queuing
 * - DeckLinkStatistics: Handles FPS calculation and statistics
 * - DeckLinkFormatManager: Manages format detection and changes
 * - DeckLinkDeviceInitializer: Handles device discovery and initialization
 * 
 * v1.6.1: TRUE zero-copy for UYVY format:
 * - UYVY sent directly to NDI without conversion
 * - Pre-allocated buffers only for non-UYVY formats
 * - Direct callback is the ONLY mode (no queuing for low latency)
 * - Removed low-latency mode flag - it's always on
 */
class DeckLinkCaptureDevice : public ICaptureDevice {
public:
    DeckLinkCaptureDevice();
    ~DeckLinkCaptureDevice() override;

    // ICaptureDevice interface
    bool Initialize(const std::string& deviceName) override;
    bool StartCapture() override;
    void StopCapture() override;
    bool GetNextFrame(FrameData& frame) override;
    std::string GetDeviceName() const override;
    bool IsCapturing() const override;
    std::vector<std::string> GetSupportedFormats() const override;
    bool SetFormat(const std::string& format) override;
    void GetStatistics(CaptureStatistics& stats) const override;

    // DeckLink specific methods (called by callback)
    bool InitializeFromDevice(IDeckLink* device, const std::string& deviceName);
    void OnFrameArrived(IDeckLinkVideoInputFrame* videoFrame);
    void OnFormatChanged(BMDVideoInputFormatChangedEvents events, 
                        IDeckLinkDisplayMode* newMode,
                        BMDDetectedVideoInputFormatFlags flags);
    
    // Frame callback for immediate delivery (v1.1.4)
    using FrameCallback = std::function<void(const FrameData&)>;
    void SetFrameCallback(FrameCallback callback) { m_frameCallback = callback; }
    
private:
    // Device management
    CComPtr<IDeckLink> m_device;
    CComPtr<IDeckLinkInput> m_deckLinkInput;
    CComPtr<IDeckLinkProfileAttributes> m_attributes;
    
    // Refactored components (v1.2.0)
    std::unique_ptr<DeckLinkCaptureCallback> m_callback;
    std::unique_ptr<DeckLinkFrameQueue> m_frameQueue;
    std::unique_ptr<DeckLinkStatistics> m_statistics;
    std::unique_ptr<DeckLinkFormatManager> m_formatManager;
    std::unique_ptr<DeckLinkDeviceInitializer> m_deviceInitializer;
    
    // Device info
    std::string m_deviceName;
    std::string m_serialNumber;
    
    // Capture state
    std::atomic<bool> m_isCapturing;
    std::atomic<bool> m_hasSignal;
    std::atomic<std::chrono::steady_clock::time_point> m_lastFrameTime;
    std::chrono::high_resolution_clock::time_point m_captureStartTime;
    
    // Current format
    BMDPixelFormat m_pixelFormat;
    BMDDisplayMode m_displayMode;
    std::atomic<long> m_width;
    std::atomic<long> m_height;
    int64_t m_frameDuration;
    int64_t m_frameTimescale;
    
    // Format converter
    std::unique_ptr<IFormatConverter> m_formatConverter;
    
    // Direct frame callback (v1.1.4)
    FrameCallback m_frameCallback;
    
    // Performance optimizations (v1.6.1)
    std::vector<uint8_t> m_preallocatedBuffer;  // Pre-allocated conversion buffer
    size_t m_preallocatedBufferSize{0};
    std::atomic<bool> m_zeroCopyLogged{false};
    
    // Performance tracking (v1.6.1)
    std::atomic<uint64_t> m_zeroCopyFrames{0};
    std::atomic<uint64_t> m_directCallbackFrames{0};
    
    // Helper methods
    void ProcessFrameForCallback(void* frameBytes, int width, int height, 
                                BMDPixelFormat pixelFormat,
                                std::chrono::steady_clock::time_point timestamp);
    void ProcessFrameZeroCopy(void* frameBytes, int width, int height,
                             BMDPixelFormat pixelFormat,
                             std::chrono::steady_clock::time_point timestamp);
    void PreallocateBuffers(int width, int height);
};
