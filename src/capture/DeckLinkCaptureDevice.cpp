// DeckLinkCaptureDevice.cpp
#include "DeckLinkCaptureDevice.h"
#include "capture/DeckLinkCaptureCallback.h"
#include "capture/DeckLinkFrameQueue.h"
#include "capture/DeckLinkStatistics.h"
#include "capture/DeckLinkFormatManager.h"
#include "capture/DeckLinkDeviceInitializer.h"
#include "FormatConverterFactory.h"
#include <iostream>
#include <iomanip>

// DeckLink SDK includes
#include "DeckLinkAPI_h.h"

// Include the DeckLinkAPI_i.c file for GUIDs
extern "C" {
    #include "DeckLinkAPI_i.c"
}

#pragma comment(lib, "comsuppw.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

// Constants from reference implementation
constexpr int MAX_CONSECUTIVE_ERRORS = 10;
constexpr int FRAME_TIMEOUT_MS = 5000;

DeckLinkCaptureDevice::DeckLinkCaptureDevice()
    : m_isCapturing(false)
    , m_hasSignal(false)
    , m_pixelFormat(bmdFormat8BitYUV)
    , m_displayMode(bmdModeUnknown)
    , m_width(1920)
    , m_height(1080)
    , m_frameDuration(1001)
    , m_frameTimescale(60000) {
    
    // Initialize components
    m_frameQueue = std::make_unique<DeckLinkFrameQueue>();
    m_statistics = std::make_unique<DeckLinkStatistics>();
    m_formatManager = std::make_unique<DeckLinkFormatManager>();
    m_deviceInitializer = std::make_unique<DeckLinkDeviceInitializer>();
    m_formatConverter = FormatConverterFactory::Create();
    
    m_lastFrameTime = std::chrono::steady_clock::now();
}

DeckLinkCaptureDevice::~DeckLinkCaptureDevice() {
    StopCapture();
}

bool DeckLinkCaptureDevice::Initialize(const std::string& deviceName) {
    try {
        DeckLinkDeviceInitializer::DeviceInfo deviceInfo;
        
        // Create callback before initialization
        m_callback = std::make_unique<DeckLinkCaptureCallback>(this);
        
        // Initialize device
        if (!m_deviceInitializer->Initialize(deviceName, m_device, m_deckLinkInput, 
                                            m_attributes, deviceInfo, m_callback.get())) {
            return false;
        }
        
        m_deviceName = deviceInfo.name;
        m_serialNumber = deviceInfo.serialNumber;
        
        return true;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in Initialize: " << e.what() << std::endl;
        return false;
    }
}

bool DeckLinkCaptureDevice::InitializeFromDevice(IDeckLink* device, const std::string& deviceName) {
    try {
        DeckLinkDeviceInitializer::DeviceInfo deviceInfo;
        
        // Create callback before initialization
        m_callback = std::make_unique<DeckLinkCaptureCallback>(this);
        
        // Initialize from existing device
        if (!m_deviceInitializer->InitializeFromDevice(device, deviceName, m_deckLinkInput,
                                                       m_attributes, deviceInfo, m_callback.get())) {
            return false;
        }
        
        m_deviceName = deviceInfo.name;
        m_serialNumber = deviceInfo.serialNumber;
        
        return true;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in InitializeFromDevice: " << e.what() << std::endl;
        return false;
    }
}

bool DeckLinkCaptureDevice::StartCapture() {
    if (m_isCapturing) {
        return true;
    }
    
    try {
        std::cout << "[DeckLink] Starting capture..." << std::endl;
        
        // Find best display mode
        long width = m_width;
        long height = m_height;
        if (!m_formatManager->FindBestDisplayMode(m_deckLinkInput, m_displayMode,
                                                 width, height, m_frameDuration, m_frameTimescale)) {
            std::cerr << "[DeckLink] No display modes available" << std::endl;
            return false;
        }
        m_width = width;
        m_height = height;
        
        // Enable video input
        if (!m_formatManager->EnableVideoInput(m_deckLinkInput, m_displayMode, m_pixelFormat)) {
            return false;
        }
        
        // Start streams
        HRESULT result = m_deckLinkInput->StartStreams();
        if (result != S_OK) {
            std::cerr << "[DeckLink] Failed to start streams" << std::endl;
            m_deckLinkInput->DisableVideoInput();
            return false;
        }
        
        // Reset statistics
        m_statistics->Reset();
        m_captureStartTime = std::chrono::high_resolution_clock::now();
        m_lastFrameTime = std::chrono::steady_clock::now();
        m_isCapturing = true;
        
        std::cout << "[DeckLink] Capture started successfully" << std::endl;
        return true;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in StartCapture: " << e.what() << std::endl;
        return false;
    }
}

void DeckLinkCaptureDevice::StopCapture() {
    if (!m_isCapturing) {
        return;
    }
    
    std::cout << "[DeckLink] Stopping capture..." << std::endl;
    
    m_isCapturing = false;
    m_frameQueue->StopCapture();
    
    // Stop streams
    if (m_deckLinkInput) {
        m_deckLinkInput->StopStreams();
        m_deckLinkInput->DisableVideoInput();
        
        if (m_callback) {
            m_deckLinkInput->SetCallback(nullptr);
        }
    }
    
    // Clear frame queue
    m_frameQueue->Clear();
    
    // Log final statistics
    m_statistics->LogStatistics(m_frameTimescale, m_frameDuration);
    std::cout << "[DeckLink] Capture stopped. Total frames: " << m_statistics->GetFrameCount() << std::endl;
}

void DeckLinkCaptureDevice::OnFrameArrived(IDeckLinkVideoInputFrame* videoFrame) {
    try {
        // Update last frame time
        m_lastFrameTime = std::chrono::steady_clock::now();
        
        // Check for valid frame
        BMDFrameFlags flags = videoFrame->GetFlags();
        if (flags & bmdFrameHasNoInputSource) {
            m_hasSignal = false;
            // Log periodically like in reference
            static auto lastNoSignalLog = std::chrono::steady_clock::now();
            auto now = std::chrono::steady_clock::now();
            if (std::chrono::duration_cast<std::chrono::seconds>(now - lastNoSignalLog).count() >= 10) {
                std::cout << "[DeckLink] No input signal (logged every 10s)" << std::endl;
                lastNoSignalLog = now;
            }
            return;
        }
        
        // Signal restored
        if (!m_hasSignal) {
            m_hasSignal = true;
            std::cout << "[DeckLink] Input signal detected" << std::endl;
        }
        
        // Get frame dimensions
        long frameWidth = videoFrame->GetWidth();
        long frameHeight = videoFrame->GetHeight();
        
        // Update dimensions if changed
        if (frameWidth != m_width || frameHeight != m_height) {
            m_width = frameWidth;
            m_height = frameHeight;
            std::cout << "[DeckLink] Frame dimensions: " << m_width << "x" << m_height << std::endl;
        }
        
        // Get video buffer interface (from reference)
        CComPtr<IDeckLinkVideoBuffer> videoBuffer;
        HRESULT result = videoFrame->QueryInterface(IID_IDeckLinkVideoBuffer, (void**)&videoBuffer);
        if (result != S_OK) {
            m_statistics->RecordDroppedFrame();
            return;
        }
        
        // Prepare buffer for CPU read access
        result = videoBuffer->StartAccess(bmdBufferAccessRead);
        if (result != S_OK) {
            m_statistics->RecordDroppedFrame();
            return;
        }
        
        // Get pointer to frame data
        void* frameBytes = nullptr;
        result = videoBuffer->GetBytes(&frameBytes);
        if (result != S_OK) {
            videoBuffer->EndAccess(bmdBufferAccessRead);
            m_statistics->RecordDroppedFrame();
            return;
        }
        
        // Process frame with direct callback if available (v1.1.4)
        if (m_frameCallback) {
            ProcessFrameForCallback(frameBytes, frameWidth, frameHeight, 
                                   m_pixelFormat, std::chrono::steady_clock::now());
        } else {
            // Queue frame
            size_t frameSize = videoFrame->GetRowBytes() * frameHeight;
            auto droppedFrames = m_statistics->GetDroppedFrames();
            m_frameQueue->AddFrame(frameBytes, frameSize, frameWidth, frameHeight,
                                  m_pixelFormat, const_cast<std::atomic<uint64_t>&>(droppedFrames));
        }
        
        // End buffer access
        videoBuffer->EndAccess(bmdBufferAccessRead);
        
        // Update statistics
        m_statistics->RecordFrame();
        
        // Log statistics if needed
        if (m_statistics->ShouldLogStatistics()) {
            m_statistics->LogStatistics(m_frameTimescale, m_frameDuration);
        }
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in OnFrameArrived: " << e.what() << std::endl;
        m_statistics->RecordDroppedFrame();
    }
}

void DeckLinkCaptureDevice::ProcessFrameForCallback(void* frameBytes, int width, int height,
                                                   BMDPixelFormat pixelFormat,
                                                   std::chrono::steady_clock::time_point timestamp) {
    // Prepare FrameData for callback
    FrameData frame;
    frame.width = width;
    frame.height = height;
    frame.timestamp = timestamp;
    
    // Calculate stride
    int sourceStride = (pixelFormat == bmdFormat8BitBGRA) ? 
                       width * 4 : width * 2;
    
    if (pixelFormat == bmdFormat8BitBGRA) {
        // BGRA format - can use directly
        frame.format = FrameData::FrameFormat::BGRA;
        frame.stride = sourceStride;
        frame.data.resize(sourceStride * height);
        memcpy(frame.data.data(), frameBytes, frame.data.size());
    } else if (pixelFormat == bmdFormat8BitYUV) {
        // UYVY format - convert to BGRA for consistency
        frame.format = FrameData::FrameFormat::BGRA;
        frame.stride = width * 4;
        frame.data.resize(frame.stride * height);
        
        if (!m_formatConverter->ConvertUYVYToBGRA(
            static_cast<uint8_t*>(frameBytes), frame.data.data(),
            width, height, sourceStride)) {
            m_statistics->RecordDroppedFrame();
            return;
        }
    } else {
        // Unsupported format
        m_statistics->RecordDroppedFrame();
        return;
    }
    
    // Deliver frame immediately via callback
    m_frameCallback(frame);
}

void DeckLinkCaptureDevice::OnFormatChanged(BMDVideoInputFormatChangedEvents events,
                                           IDeckLinkDisplayMode* newMode,
                                           BMDDetectedVideoInputFormatFlags flags) {
    try {
        long width = m_width;
        long height = m_height;
        
        if (m_formatManager->HandleFormatChange(events, newMode, flags, m_deckLinkInput,
                                               m_displayMode, m_pixelFormat,
                                               width, height, m_frameDuration, m_frameTimescale)) {
            m_width = width;
            m_height = height;
        }
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in OnFormatChanged: " << e.what() << std::endl;
    }
}

bool DeckLinkCaptureDevice::GetNextFrame(FrameData& frame) {
    if (!m_isCapturing) {
        return false;
    }
    
    // Check for frame timeout (from reference)
    auto now = std::chrono::steady_clock::now();
    auto timeSinceLastFrame = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - m_lastFrameTime.load()).count();
    
    if (timeSinceLastFrame > FRAME_TIMEOUT_MS) {
        std::cerr << "[DeckLink] Frame timeout (" << timeSinceLastFrame << "ms)" << std::endl;
        return false;
    }
    
    // Get frame from queue
    DeckLinkFrameQueue::QueuedFrame queuedFrame;
    if (!m_frameQueue->GetNextFrame(queuedFrame, 100)) {
        return false;
    }
    
    // Convert format if needed
    frame.width = queuedFrame.width;
    frame.height = queuedFrame.height;
    frame.timestamp = queuedFrame.timestamp;
    
    // Calculate stride
    int sourceStride = (queuedFrame.pixelFormat == bmdFormat8BitBGRA) ? 
                       queuedFrame.width * 4 : queuedFrame.width * 2;
    
    if (queuedFrame.pixelFormat == bmdFormat8BitBGRA) {
        // BGRA format - can use directly
        frame.format = FrameData::FrameFormat::BGRA;
        frame.stride = sourceStride;
        frame.data = std::move(queuedFrame.data);
    } else if (queuedFrame.pixelFormat == bmdFormat8BitYUV) {
        // UYVY format - convert to BGRA
        frame.format = FrameData::FrameFormat::BGRA;
        frame.stride = queuedFrame.width * 4;
        frame.data.resize(frame.stride * frame.height);
        
        if (!m_formatConverter->ConvertUYVYToBGRA(
            queuedFrame.data.data(), frame.data.data(),
            queuedFrame.width, queuedFrame.height, sourceStride)) {
            return false;
        }
    } else {
        // Unsupported format
        return false;
    }
    
    return true;
}

std::string DeckLinkCaptureDevice::GetDeviceName() const {
    return m_deviceName;
}

bool DeckLinkCaptureDevice::IsCapturing() const {
    return m_isCapturing;
}

std::vector<std::string> DeckLinkCaptureDevice::GetSupportedFormats() const {
    if (!m_deckLinkInput) {
        return {};
    }
    
    return m_formatManager->GetSupportedFormats(m_deckLinkInput);
}

bool DeckLinkCaptureDevice::SetFormat(const std::string& format) {
    // Not implemented - format is auto-detected
    return false;
}

void DeckLinkCaptureDevice::GetStatistics(CaptureStatistics& stats) const {
    m_statistics->GetStatistics(stats, m_captureStartTime);
}
