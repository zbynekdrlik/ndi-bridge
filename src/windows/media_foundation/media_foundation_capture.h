// media_foundation_capture.h
#pragma once

#include "../../common/capture_interface.h"
#include "mf_capture_device.h"
#include "mf_video_capture.h"
#include <memory>
#include <string>

namespace ndi_bridge {

// Media Foundation implementation of ICaptureDevice
class MediaFoundationCapture : public ICaptureDevice {
public:
    MediaFoundationCapture();
    ~MediaFoundationCapture() override;
    
    // ICaptureDevice implementation
    std::vector<std::pair<std::string, std::string>> EnumerateDevices() override;
    bool SelectDevice(const std::string& device_id) override;
    bool Initialize() override;
    void Shutdown() override;
    bool StartCapture(FrameCallback callback) override;
    void StopCapture() override;
    bool IsCapturing() const override;
    bool SetOutputFormat(int width, int height, uint32_t fps_num, uint32_t fps_den) override;
    void GetCurrentFormat(int& width, int& height, uint32_t& fps_num, uint32_t& fps_den, uint32_t& fourcc) override;
    bool IsDeviceValid() const override;
    std::string GetLastError() const override;
    
private:
    // Helper to reinitialize on device errors
    bool ReinitializeOnError(HRESULT hr);
    
    // Convert wide string to UTF-8
    static std::string WideToUtf8(const std::wstring& wide);
    static std::wstring Utf8ToWide(const std::string& utf8);
    
private:
    std::unique_ptr<media_foundation::MFCaptureDevice> device_manager_;
    std::unique_ptr<media_foundation::MFVideoCapture> video_capture_;
    
    IMFActivate* current_activate_;
    IMFSourceReader* current_reader_;
    
    std::wstring selected_device_name_;
    std::string last_error_;
    bool initialized_;
    
    // Retry state
    int reinit_attempts_;
    static constexpr int kMaxReinitAttempts = 3;
};

} // namespace ndi_bridge
