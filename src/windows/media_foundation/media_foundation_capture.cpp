// media_foundation_capture.cpp
#include "media_foundation_capture.h"
#include "mf_error_handling.h"
#include <codecvt>
#include <locale>
#include <iostream>
#include <chrono>

namespace ndi_bridge {

MediaFoundationCapture::MediaFoundationCapture()
    : current_activate_(nullptr)
    , current_reader_(nullptr)
    , current_source_(nullptr)
    , initialized_(false)
    , reinit_attempts_(0) {
    device_manager_ = std::make_unique<media_foundation::MFCaptureDevice>();
    video_capture_ = std::make_unique<media_foundation::MFVideoCapture>();
}

MediaFoundationCapture::~MediaFoundationCapture() {
    // Stop capture first
    if (isCapturing()) {
        stopCapture();
    }
    
    // Then shutdown device properly
    shutdownDevice();
}

std::vector<ICaptureDevice::DeviceInfo> MediaFoundationCapture::enumerateDevices() {
    std::vector<ICaptureDevice::DeviceInfo> result;
    std::vector<media_foundation::DeviceInfo> devices;
    
    HRESULT hr = device_manager_->EnumerateDevices(devices);
    if (FAILED(hr)) {
        last_error_ = "Failed to enumerate devices: " + media_foundation::MFErrorHandler::HResultToString(hr);
        has_error_ = true;
        return result;
    }
    
    for (const auto& device : devices) {
        ICaptureDevice::DeviceInfo info;
        info.name = wideToUtf8(device.friendly_name);
        info.id = info.name;  // Use friendly name as ID for simplicity
        result.push_back(info);
    }
    
    return result;
}

bool MediaFoundationCapture::startCapture(const std::string& device_name) {
    // Initialize device if not already done
    if (!initialized_) {
        if (!initializeDevice(device_name)) {
            return false;
        }
    }
    
    // Configure output format
    video_capture_->ConfigureOutputFormat();
    
    // Get negotiated format
    HRESULT hr = video_capture_->GetNegotiatedFormat();
    if (FAILED(hr)) {
        last_error_ = "Failed to negotiate format";
        has_error_ = true;
        shutdownDevice();
        return false;
    }
    
    // Set up frame callback - MFVideoCapture already uses the correct interface
    if (frame_callback_) {
        video_capture_->SetFrameCallback(frame_callback_);
    }
    
    hr = video_capture_->StartCapture();
    if (FAILED(hr)) {
        last_error_ = "Failed to start capture";
        has_error_ = true;
        return false;
    }
    
    has_error_ = false;
    return true;
}

void MediaFoundationCapture::stopCapture() {
    if (video_capture_) {
        video_capture_->StopCapture();
    }
}

bool MediaFoundationCapture::isCapturing() const {
    return video_capture_ && video_capture_->IsCapturing();
}

void MediaFoundationCapture::setFrameCallback(FrameCallback callback) {
    frame_callback_ = std::move(callback);
}

void MediaFoundationCapture::setErrorCallback(ErrorCallback callback) {
    error_callback_ = std::move(callback);
}

bool MediaFoundationCapture::hasError() const {
    return has_error_ || (video_capture_ && !video_capture_->GetLastError().empty());
}

std::string MediaFoundationCapture::getLastError() const {
    if (video_capture_ && !video_capture_->GetLastError().empty()) {
        return video_capture_->GetLastError();
    }
    return last_error_;
}

bool MediaFoundationCapture::initializeDevice(const std::string& device_name) {
    selected_device_name_ = device_name.empty() ? L"" : utf8ToWide(device_name);
    
    // Re-enumerate and find device by name (for reconnection support)
    std::vector<media_foundation::DeviceInfo> devices;
    HRESULT hr = device_manager_->EnumerateDevices(devices);
    if (FAILED(hr) || devices.empty()) {
        last_error_ = "No capture devices found";
        has_error_ = true;
        return false;
    }
    
    // If no device name specified, this should have been handled by main.cpp interactive selection
    // But keep the fallback to first device for backward compatibility
    if (selected_device_name_.empty()) {
        selected_device_name_ = devices[0].friendly_name;
    }
    
    // Find device by name
    bool device_found = false;
    for (const auto& device : devices) {
        if (device.friendly_name == selected_device_name_) {
            device_found = true;
            break;
        }
    }
    
    if (!device_found) {
        last_error_ = "Device not found: " + wideToUtf8(selected_device_name_);
        has_error_ = true;
        return false;
    }
    
    // Find device by name
    hr = device_manager_->FindDeviceByName(selected_device_name_, &current_activate_);
    if (FAILED(hr)) {
        last_error_ = "Failed to find device: " + wideToUtf8(selected_device_name_);
        has_error_ = true;
        return false;
    }
    
    // Create media source and keep reference for proper shutdown
    hr = device_manager_->CreateMediaSource(current_activate_, &current_source_);
    if (FAILED(hr)) {
        last_error_ = "Failed to create media source: " + media_foundation::MFErrorHandler::HResultToString(hr);
        has_error_ = true;
        if (current_activate_) {
            current_activate_->Release();
            current_activate_ = nullptr;
        }
        return false;
    }
    
    // Create source reader from media source
    hr = device_manager_->CreateSourceReader(current_source_, &current_reader_);
    if (FAILED(hr)) {
        last_error_ = "Failed to create source reader: " + media_foundation::MFErrorHandler::HResultToString(hr);
        has_error_ = true;
        shutdownDevice();
        return false;
    }
    
    // Initialize video capture
    hr = video_capture_->Initialize(current_reader_);
    if (FAILED(hr)) {
        last_error_ = "Failed to initialize video capture";
        has_error_ = true;
        shutdownDevice();
        return false;
    }
    
    initialized_ = true;
    reinit_attempts_ = 0;
    has_error_ = false;
    return true;
}

void MediaFoundationCapture::shutdownDevice() {
    // 1. Stop video capture first
    if (video_capture_) {
        video_capture_->StopCapture();
        video_capture_.reset();  // Release the video capture
    }
    
    // 2. Flush and release source reader
    if (current_reader_) {
        // Flush all streams to ensure no pending operations
        current_reader_->Flush(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS));
        current_reader_->Release();
        current_reader_ = nullptr;
    }
    
    // 3. Shutdown the media source properly
    if (current_source_) {
        // Stop the media source
        current_source_->Stop();
        
        // Shut it down completely
        current_source_->Shutdown();
        
        // Now release
        current_source_->Release();
        current_source_ = nullptr;
    }
    
    // 4. Release the activate object
    if (current_activate_) {
        // Shut down the activate object to release the device
        current_activate_->ShutdownObject();
        current_activate_->Release();
        current_activate_ = nullptr;
    }
    
    // 5. Clear cached devices in device manager
    device_manager_->Cleanup();
    
    initialized_ = false;
}

bool MediaFoundationCapture::reinitializeOnError(HRESULT hr) {
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
    shutdownDevice();
    
    // Wait a bit
    std::this_thread::sleep_for(std::chrono::milliseconds(1000 * reinit_attempts_));
    
    // Try to initialize again - this will re-enumerate devices
    return initializeDevice(wideToUtf8(selected_device_name_));
}

std::string MediaFoundationCapture::wideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return "";
    
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) return "";
    
    std::string result(size - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &result[0], size, nullptr, nullptr);
    return result;
}

std::wstring MediaFoundationCapture::utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return L"";
    
    int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    if (size <= 0) return L"";
    
    std::wstring result(size - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &result[0], size);
    return result;
}

} // namespace ndi_bridge
