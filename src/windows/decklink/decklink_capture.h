// decklink_capture.h - DeckLink capture interface
#pragma once

#include "../../common/capture_interface.h"
#include "../../capture/DeckLinkDeviceEnumerator.h"
#include "../../capture/DeckLinkCaptureDevice.h"
#include <memory>
#include <string>
#include <mutex>
#include <atomic>

namespace ndi_bridge {

/**
 * @brief DeckLink implementation of ICaptureDevice
 * 
 * This class provides video capture functionality using Blackmagic DeckLink devices.
 * It handles device enumeration, capture control, and frame delivery.
 * 
 * Version: 1.1.1 - Fixed frame drop issue by using direct callbacks
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
    // Convert internal FrameData to ICaptureDevice VideoFormat
    VideoFormat convertFrameFormat(const FrameData& frame) const;
    
    // Frame received callback from DeckLinkCaptureDevice
    void onFrameReceived(const FrameData& frame);
    
    // Device management
    std::unique_ptr<DeckLinkDeviceEnumerator> m_enumerator;
    std::unique_ptr<DeckLinkCaptureDevice> m_captureDevice;
    
    // State
    std::string m_currentDeviceName;
    mutable std::mutex m_mutex;
    std::string m_lastError;
    std::atomic<bool> m_hasError;
    
    // Callbacks
    FrameCallback m_frameCallback;
    ErrorCallback m_errorCallback;
};

} // namespace ndi_bridge