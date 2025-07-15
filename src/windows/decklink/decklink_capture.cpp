// decklink_capture.cpp - DeckLink capture implementation
#include "decklink_capture.h"
#include <iostream>
#include <sstream>
#include <chrono>

namespace ndi_bridge {

DeckLinkCapture::DeckLinkCapture()
    : m_hasError(false)
    , m_threadRunning(false) {
    
    m_enumerator = std::make_unique<DeckLinkDeviceEnumerator>();
}

DeckLinkCapture::~DeckLinkCapture() {
    stopCapture();
}

std::vector<ICaptureDevice::DeviceInfo> DeckLinkCapture::enumerateDevices() {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    try {
        // Use the DeckLink enumerator to get devices
        auto deckLinkDevices = m_enumerator->EnumerateDevices();
        
        // Convert to ICaptureDevice::DeviceInfo format
        std::vector<DeviceInfo> devices;
        for (const auto& dlDevice : deckLinkDevices) {
            DeviceInfo info;
            info.name = dlDevice.name;
            info.id = dlDevice.name;  // DeckLink uses name as ID
            devices.push_back(info);
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
        
        // Start frame processing thread
        m_threadRunning = true;
        m_frameThread = std::thread(&DeckLinkCapture::frameProcessingThread, this);
        
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
    // Stop thread first
    if (m_threadRunning) {
        m_threadRunning = false;
        if (m_frameThread.joinable()) {
            m_frameThread.join();
        }
    }
    
    // Then stop device
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_captureDevice) {
        m_captureDevice->StopCapture();
        m_captureDevice.reset();
    }
    m_currentDeviceName.clear();
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

void DeckLinkCapture::frameProcessingThread() {
    while (m_threadRunning) {
        try {
            FrameData frame;
            
            // Try to get next frame
            if (m_captureDevice && m_captureDevice->GetNextFrame(frame)) {
                onFrameReceived(frame);
            } else {
                // No frame available, sleep briefly
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        }
        catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_lastError = std::string("Frame processing error: ") + e.what();
            m_hasError = true;
            if (m_errorCallback) {
                m_errorCallback(m_lastError);
            }
        }
    }
}

void DeckLinkCapture::onFrameReceived(const FrameData& frame) {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    if (!m_frameCallback) {
        return;
    }
    
    // Convert frame format
    VideoFormat format = convertFrameFormat(frame);
    
    // Calculate timestamp in nanoseconds
    auto now = std::chrono::steady_clock::now();
    auto duration = now.time_since_epoch();
    int64_t timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count();
    
    // Call the callback
    m_frameCallback(frame.data.data(), frame.data.size(), timestamp, format);
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
    
    // Default to 60fps for DeckLink (will be updated based on actual capture)
    format.fps_numerator = 60000;
    format.fps_denominator = 1001;
    
    return format;
}

} // namespace ndi_bridge
