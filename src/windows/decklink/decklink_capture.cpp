// decklink_capture.cpp - DeckLink capture implementation
#include "decklink_capture.h"
#include <iostream>
#include <sstream>
#include <chrono>

namespace ndi_bridge {

DeckLinkCapture::DeckLinkCapture()
    : m_hasError(false) {
    
    m_enumerator = std::make_unique<DeckLinkDeviceEnumerator>();
}

DeckLinkCapture::~DeckLinkCapture() {
    stopCapture();
}

std::vector<ICaptureDevice::DeviceInfo> DeckLinkCapture::enumerateDevices() {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    try {
        // Use the DeckLink enumerator to get devices
        if (!m_enumerator->EnumerateDevices()) {
            // Failed to enumerate devices
            m_lastError = "Failed to enumerate DeckLink devices";
            m_hasError = true;
            if (m_errorCallback) {
                m_errorCallback(m_lastError);
            }
            return {};
        }
        
        // Convert to ICaptureDevice::DeviceInfo format
        std::vector<DeviceInfo> devices;
        int deviceCount = m_enumerator->GetDeviceCount();
        
        for (int i = 0; i < deviceCount; ++i) {
            DeckLinkDeviceEnumerator::DeviceInfo dlInfo;
            if (m_enumerator->GetDeviceInfo(i, dlInfo)) {
                DeviceInfo info;
                info.name = dlInfo.name;
                info.id = dlInfo.name;  // DeckLink uses name as ID
                devices.push_back(info);
            }
        }
        
        return devices;
    }
    catch (const std::exception& e) {
        m_lastError = std::string("Failed to enumerate DeckLink devices: ") + e.what();
        m_hasError = true;
        if (m_errorCallback) {
            m_errorCallback(m_lastError);
        }
        return {};
    }
}

bool DeckLinkCapture::startCapture(const std::string& device_name) {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    if (m_captureDevice && m_captureDevice->IsCapturing()) {
        stopCapture();
    }
    
    try {
        // Create capture device
        m_captureDevice = std::make_unique<DeckLinkCaptureDevice>();
        
        // Use first device if no name specified
        std::string targetDevice = device_name;
        if (targetDevice.empty()) {
            auto devices = enumerateDevices();
            if (devices.empty()) {
                throw std::runtime_error("No DeckLink devices found");
            }
            targetDevice = devices[0].name;
        }
        
        // Set frame callback directly on the device - no polling needed!
        m_captureDevice->SetFrameCallback(
            [this](const FrameData& frame) {
                onFrameReceived(frame);
            }
        );
        
        // Initialize device
        if (!m_captureDevice->Initialize(targetDevice)) {
            throw std::runtime_error("Failed to initialize DeckLink device: " + targetDevice);
        }
        
        // Start capture
        if (!m_captureDevice->StartCapture()) {
            throw std::runtime_error("Failed to start DeckLink capture");
        }
        
        m_currentDeviceName = targetDevice;
        m_hasError = false;
        
        // No polling thread needed - frames come via callback
        return true;
    }
    catch (const std::exception& e) {
        m_lastError = e.what();
        m_hasError = true;
        if (m_errorCallback) {
            m_errorCallback(m_lastError);
        }
        
        // Cleanup
        if (m_captureDevice) {
            m_captureDevice.reset();
        }
        
        return false;
    }
}

void DeckLinkCapture::stopCapture() {
    // Store the capture device pointer and release it from the unique_ptr
    // This allows us to stop it without holding the mutex
    std::unique_ptr<DeckLinkCaptureDevice> deviceToStop;
    
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_captureDevice) {
            // Move ownership to local variable
            deviceToStop = std::move(m_captureDevice);
            m_currentDeviceName.clear();
        }
    }
    
    // Now stop the capture without holding the mutex
    // This allows the callback thread to acquire the mutex if needed
    if (deviceToStop) {
        deviceToStop->StopCapture();
        // deviceToStop will be destroyed when it goes out of scope
    }
}

bool DeckLinkCapture::isCapturing() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_captureDevice && m_captureDevice->IsCapturing();
}

void DeckLinkCapture::setFrameCallback(FrameCallback callback) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_frameCallback = callback;
}

void DeckLinkCapture::setErrorCallback(ErrorCallback callback) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_errorCallback = callback;
}

bool DeckLinkCapture::hasError() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_hasError;
}

std::string DeckLinkCapture::getLastError() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_lastError;
}

void DeckLinkCapture::onFrameReceived(const FrameData& frame) {
    // This is called directly from DeckLink callback thread
    // Check if we're still capturing before acquiring the mutex
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        
        // Double-check we're still capturing and have a callback
        if (!m_captureDevice || !m_frameCallback) {
            return;
        }
    }
    
    // Convert frame format
    VideoFormat format = convertFrameFormat(frame);
    
    // Use frame timestamp if available, otherwise generate one
    int64_t timestamp = frame.timestamp.time_since_epoch().count();
    if (timestamp == 0) {
        auto now = std::chrono::steady_clock::now();
        auto duration = now.time_since_epoch();
        timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count();
    }
    
    // Call the callback - do this outside the mutex to avoid holding it too long
    FrameCallback callback;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        callback = m_frameCallback;
    }
    
    if (callback) {
        callback(frame.data.data(), frame.data.size(), timestamp, format);
    }
}

ICaptureDevice::VideoFormat DeckLinkCapture::convertFrameFormat(const FrameData& frame) const {
    VideoFormat format;
    format.width = frame.width;
    format.height = frame.height;
    format.stride = frame.stride;
    
    // Convert FrameData::FrameFormat to string
    switch (frame.format) {
        case FrameData::FrameFormat::BGRA:
            format.pixel_format = "BGRA";
            break;
        case FrameData::FrameFormat::UYVY:
            format.pixel_format = "UYVY";
            break;
        case FrameData::FrameFormat::YUV420:
            format.pixel_format = "YUV420";
            break;
        case FrameData::FrameFormat::NV12:
            format.pixel_format = "NV12";
            break;
        case FrameData::FrameFormat::RGB24:
            format.pixel_format = "RGB24";
            break;
        default:
            format.pixel_format = "Unknown";
            break;
    }
    
    // Get actual frame rate from device
    format.fps_numerator = 60000;  // Default
    format.fps_denominator = 1001;
    
    // TODO: Get actual frame rate from DeckLinkCaptureDevice
    
    return format;
}

} // namespace ndi_bridge
