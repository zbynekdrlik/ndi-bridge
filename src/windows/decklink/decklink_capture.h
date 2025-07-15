// decklink_capture.h - DeckLink capture implementation
#pragma once

#include "../../common/capture_interface.h"
#include "../../capture/DeckLinkCaptureDevice.h"
#include "../../capture/DeckLinkDeviceEnumerator.h"
#include <memory>
#include <mutex>
#include <thread>
#include <atomic>

namespace ndi_bridge {

/**
 * @brief DeckLink implementation of ICaptureDevice
 * 
 * Provides video capture functionality using Blackmagic DeckLink devices.
 * This class adapts the DeckLinkCaptureDevice to the common capture interface.
 * 
 * Version: 1.1.2
 */
class DeckLinkCapture : public ICaptureDevice {
public:
    DeckLinkCapture();
    ~DeckLinkCapture() override;
    
    // ICaptureDevice implementation
    std::vector<DeviceInfo> enumerateDevices() override;
    bool startCapture(const std::string& device_name = "") override;
    void stopCapture() override;
    bool isCapturing() const override;
    void setFrameCallback(FrameCallback callback) override;
    void setErrorCallback(ErrorCallback callback) override;
    bool hasError() const override;
    std::string getLastError() const override;
    
private:
    // Frame processing callback from DeckLinkCaptureDevice
    void onFrameReceived(const FrameData& frame);
    
    // Convert FrameData to VideoFormat
    VideoFormat convertFrameFormat(const FrameData& frame) const;
    
private:
    std::unique_ptr<DeckLinkCaptureDevice> m_captureDevice;
    std::unique_ptr<DeckLinkDeviceEnumerator> m_enumerator;
    
    // Callbacks
    FrameCallback m_frameCallback;
    ErrorCallback m_errorCallback;
    
    // State
    mutable std::mutex m_mutex;
    std::string m_lastError;
    bool m_hasError;
    std::string m_currentDeviceName;
    
    // Frame processing thread
    std::thread m_frameThread;
    std::atomic<bool> m_threadRunning;
    void frameProcessingThread();
};

} // namespace ndi_bridge
