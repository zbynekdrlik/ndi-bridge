// DeckLinkCaptureDevice.h
#pragma once

#include "ICaptureDevice.h"
#include "IFormatConverter.h"
#include <memory>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <chrono>
#include <atlbase.h>

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

class CaptureCallback;

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

    // DeckLink specific methods
    bool InitializeFromDevice(IDeckLink* device, const std::string& deviceName);
    void OnFrameArrived(IDeckLinkVideoInputFrame* videoFrame);
    void OnFormatChanged(BMDVideoInputFormatChangedEvents events, 
                        IDeckLinkDisplayMode* newMode,
                        BMDDetectedVideoInputFormatFlags flags);
    
private:
    struct DeviceInfo {
        std::string name;
        std::string serialNumber;
    };

    struct FrameTimestamp {
        int frameNumber;
        std::chrono::high_resolution_clock::time_point timestamp;
    };

    // Device management
    CComPtr<IDeckLink> m_device;
    CComPtr<IDeckLinkInput> m_deckLinkInput;
    CComPtr<IDeckLinkProfileAttributes> m_attributes;
    DeviceInfo m_deviceInfo;
    
    // Capture state
    std::atomic<bool> m_isCapturing;
    std::atomic<bool> m_hasSignal;
    CaptureCallback* m_callback;
    BMDPixelFormat m_pixelFormat;
    BMDDisplayMode m_displayMode;
    
    // Frame info
    std::atomic<int> m_width;
    std::atomic<int> m_height;
    BMDTimeValue m_frameDuration;
    BMDTimeScale m_frameTimescale;
    
    // Statistics
    std::atomic<uint64_t> m_frameCount;
    std::atomic<uint64_t> m_droppedFrames;
    std::atomic<std::chrono::steady_clock::time_point> m_lastFrameTime;
    std::chrono::high_resolution_clock::time_point m_captureStartTime;
    mutable std::mutex m_statsMutex;
    std::deque<FrameTimestamp> m_frameHistory;
    
    // Frame queue
    struct QueuedFrame {
        std::vector<uint8_t> data;
        int width;
        int height;
        BMDPixelFormat pixelFormat;
        std::chrono::steady_clock::time_point timestamp;
    };
    
    std::deque<QueuedFrame> m_frameQueue;
    mutable std::mutex m_queueMutex;
    std::condition_variable m_frameAvailable;
    static constexpr size_t MAX_QUEUE_SIZE = 3;
    
    // Format converter
    std::unique_ptr<IFormatConverter> m_formatConverter;
    
    // Helper methods
    bool EnableVideoInput();
    bool FindBestDisplayMode();
    std::string GetDeviceSerialNumber() const;
    std::string BSTRToString(BSTR bstr) const;
    double CalculateRollingFPS() const;
    void LogFrameStatistics();
    void ResetStatistics();
};
