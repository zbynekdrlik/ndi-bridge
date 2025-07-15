// media_foundation_capture.h
#pragma once

#include "../../common/capture_interface.h"
#include "mf_capture_device.h"
#include "mf_video_capture.h"
#include <memory>
#include <string>
#include <atomic>

namespace ndi_bridge {

/**
 * @brief Media Foundation implementation of ICaptureDevice
 * 
 * Provides video capture functionality using Windows Media Foundation.
 * 
 * Version: 1.0.8
 */
class MediaFoundationCapture : public ICaptureDevice {
public:
    MediaFoundationCapture();
    ~MediaFoundationCapture() override;
    
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
    // Initialize device by name
    bool initializeDevice(const std::string& device_name);
    
    // Shutdown current device
    void shutdownDevice();
    void shutdownDevice(bool full_shutdown);  // New overload for controlled shutdown
    
    // Helper to reinitialize on device errors
    bool reinitializeOnError(HRESULT hr);
    
    // Convert wide string to UTF-8
    static std::string wideToUtf8(const std::wstring& wide);
    static std::wstring utf8ToWide(const std::string& utf8);
    
private:
    std::unique_ptr<media_foundation::MFCaptureDevice> device_manager_;
    std::unique_ptr<media_foundation::MFVideoCapture> video_capture_;
    
    IMFActivate* current_activate_;
    IMFSourceReader* current_reader_;
    IMFMediaSource* current_source_;  // Keep reference for proper shutdown
    
    std::wstring selected_device_name_;
    std::string last_error_;
    std::atomic<bool> has_error_{false};
    bool initialized_;
    
    // Callbacks
    FrameCallback frame_callback_;
    ErrorCallback error_callback_;
    
    // Retry state
    int reinit_attempts_;
    static constexpr int kMaxReinitAttempts = 3;
};

} // namespace ndi_bridge
