// media_foundation_capture.cpp
#include "media_foundation_capture.h"
#include "mf_error_handling.h"
#include <codecvt>
#include <locale>
#include <iostream>

namespace ndi_bridge {

MediaFoundationCapture::MediaFoundationCapture()
    : current_activate_(nullptr)
    , current_reader_(nullptr)
    , initialized_(false)
    , reinit_attempts_(0) {
    device_manager_ = std::make_unique<media_foundation::MFCaptureDevice>();
    video_capture_ = std::make_unique<media_foundation::MFVideoCapture>();
}

MediaFoundationCapture::~MediaFoundationCapture() {
    Shutdown();
}

std::vector<std::pair<std::string, std::string>> MediaFoundationCapture::EnumerateDevices() {
    std::vector<std::pair<std::string, std::string>> result;
    std::vector<media_foundation::DeviceInfo> devices;
    
    HRESULT hr = device_manager_->EnumerateDevices(devices);
    if (FAILED(hr)) {
        last_error_ = "Failed to enumerate devices: " + media_foundation::MFErrorHandler::HResultToString(hr);
        return result;
    }
    
    for (const auto& device : devices) {
        // Use friendly name as both ID and display name
        std::string name = WideToUtf8(device.friendly_name);
        result.push_back({name, name});
    }
    
    return result;
}

bool MediaFoundationCapture::SelectDevice(const std::string& device_id) {
    selected_device_name_ = Utf8ToWide(device_id);
    return true;
}

bool MediaFoundationCapture::Initialize() {
    if (initialized_) {
        return true;
    }
    
    if (selected_device_name_.empty()) {
        last_error_ = "No device selected";
        return false;
    }
    
    // Find device by name
    HRESULT hr = device_manager_->FindDeviceByName(selected_device_name_, &current_activate_);
    if (FAILED(hr)) {
        last_error_ = "Failed to find device: " + WideToUtf8(selected_device_name_);
        return false;
    }
    
    // Create source reader
    hr = device_manager_->CreateSourceReaderFromActivate(current_activate_, &current_reader_);
    if (FAILED(hr)) {
        last_error_ = "Failed to create source reader: " + media_foundation::MFErrorHandler::HResultToString(hr);
        if (current_activate_) {
            current_activate_->Release();
            current_activate_ = nullptr;
        }
        return false;
    }
    
    // Initialize video capture
    hr = video_capture_->Initialize(current_reader_);
    if (FAILED(hr)) {
        last_error_ = "Failed to initialize video capture";
        Shutdown();
        return false;
    }
    
    // Configure output format
    video_capture_->ConfigureOutputFormat();
    
    // Get negotiated format
    hr = video_capture_->GetNegotiatedFormat();
    if (FAILED(hr)) {
        last_error_ = "Failed to negotiate format";
        Shutdown();
        return false;
    }
    
    initialized_ = true;
    reinit_attempts_ = 0;
    return true;
}

void MediaFoundationCapture::Shutdown() {
    if (video_capture_) {
        video_capture_->StopCapture();
    }
    
    if (current_reader_) {
        current_reader_->Release();
        current_reader_ = nullptr;
    }
    
    if (current_activate_) {
        current_activate_->Release();
        current_activate_ = nullptr;
    }
    
    initialized_ = false;
}

bool MediaFoundationCapture::StartCapture(FrameCallback callback) {
    if (!initialized_) {
        last_error_ = "Not initialized";
        return false;
    }
    
    video_capture_->SetFrameCallback(callback);
    
    HRESULT hr = video_capture_->StartCapture();
    if (FAILED(hr)) {
        last_error_ = "Failed to start capture";
        return false;
    }
    
    return true;
}

void MediaFoundationCapture::StopCapture() {
    if (video_capture_) {
        video_capture_->StopCapture();
    }
}

bool MediaFoundationCapture::IsCapturing() const {
    return video_capture_ && video_capture_->IsCapturing();
}

bool MediaFoundationCapture::SetOutputFormat(int width, int height, uint32_t fps_num, uint32_t fps_den) {
    // Media Foundation doesn't support setting specific output formats easily
    // The format is negotiated based on device capabilities
    // This could be enhanced in the future
    return false;
}

void MediaFoundationCapture::GetCurrentFormat(int& width, int& height, 
                                              uint32_t& fps_num, uint32_t& fps_den, 
                                              uint32_t& fourcc) {
    if (!video_capture_) {
        width = height = 0;
        fps_num = fps_den = 0;
        fourcc = 0;
        return;
    }
    
    GUID subtype;
    video_capture_->GetFormatInfo(width, height, fps_num, fps_den, subtype);
    
    // We always output UYVY to NDI
    fourcc = 'UYVY';
}

bool MediaFoundationCapture::IsDeviceValid() const {
    // Check if capture is still running without errors
    if (!initialized_ || !video_capture_) {
        return false;
    }
    
    // If we're capturing and haven't encountered errors, device is valid
    if (video_capture_->IsCapturing()) {
        return video_capture_->GetLastError().empty();
    }
    
    return true;
}

std::string MediaFoundationCapture::GetLastError() const {
    if (!video_capture_->GetLastError().empty()) {
        return video_capture_->GetLastError();
    }
    return last_error_;
}

bool MediaFoundationCapture::ReinitializeOnError(HRESULT hr) {
    if (reinit_attempts_ >= kMaxReinitAttempts) {
        return false;
    }
    
    reinit_attempts_++;
    
    std::cout << "Attempting to reinitialize (attempt " << reinit_attempts_ 
              << "/" << kMaxReinitAttempts << ")" << std::endl;
    
    // Check if we need to reinit Media Foundation
    if (media_foundation::MFErrorHandler::RequiresMediaFoundationReinit(hr)) {
        media_foundation::MFInitializer mf_init;
        mf_init.Reinitialize();
    }
    
    // Shutdown current session
    Shutdown();
    
    // Wait a bit
    std::this_thread::sleep_for(std::chrono::milliseconds(1000 * reinit_attempts_));
    
    // Try to initialize again
    return Initialize();
}

std::string MediaFoundationCapture::WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return "";
    
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) return "";
    
    std::string result(size - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &result[0], size, nullptr, nullptr);
    return result;
}

std::wstring MediaFoundationCapture::Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return L"";
    
    int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    if (size <= 0) return L"";
    
    std::wstring result(size - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &result[0], size);
    return result;
}

} // namespace ndi_bridge
