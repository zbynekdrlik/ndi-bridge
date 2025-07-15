// DeckLinkCaptureDevice.cpp
#include "DeckLinkCaptureDevice.h"
#include "FormatConverterFactory.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <algorithm>

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

// Capture callback class adapted from reference
class CaptureCallback : public IDeckLinkInputCallback {
private:
    std::atomic<ULONG> m_refCount;
    DeckLinkCaptureDevice* m_owner;
    
public:
    CaptureCallback(DeckLinkCaptureDevice* owner) 
        : m_refCount(1), m_owner(owner) {
    }
    
    // IUnknown methods
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv) {
        if (iid == IID_IUnknown) {
            *ppv = this;
            AddRef();
            return S_OK;
        }
        if (iid == IID_IDeckLinkInputCallback) {
            *ppv = (IDeckLinkInputCallback*)this;
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }
    
    virtual ULONG STDMETHODCALLTYPE AddRef(void) {
        return ++m_refCount;
    }
    
    virtual ULONG STDMETHODCALLTYPE Release(void) {
        ULONG refCount = --m_refCount;
        if (refCount == 0) {
            delete this;
        }
        return refCount;
    }
    
    // IDeckLinkInputCallback methods
    virtual HRESULT STDMETHODCALLTYPE VideoInputFormatChanged(
        BMDVideoInputFormatChangedEvents notificationEvents,
        IDeckLinkDisplayMode* newMode,
        BMDDetectedVideoInputFormatFlags detectedSignalFlags) {
        
        if (m_owner) {
            m_owner->OnFormatChanged(notificationEvents, newMode, detectedSignalFlags);
        }
        return S_OK;
    }
    
    virtual HRESULT STDMETHODCALLTYPE VideoInputFrameArrived(
        IDeckLinkVideoInputFrame* videoFrame,
        IDeckLinkAudioInputPacket* audioPacket) {
        
        if (m_owner && videoFrame) {
            m_owner->OnFrameArrived(videoFrame);
        }
        return S_OK;
    }
};

DeckLinkCaptureDevice::DeckLinkCaptureDevice()
    : m_isCapturing(false)
    , m_hasSignal(false)
    , m_callback(nullptr)
    , m_pixelFormat(bmdFormat8BitYUV)
    , m_displayMode(bmdModeUnknown)
    , m_width(1920)
    , m_height(1080)
    , m_frameDuration(1001)
    , m_frameTimescale(60000)
    , m_frameCount(0)
    , m_droppedFrames(0) {
    
    m_lastFrameTime = std::chrono::steady_clock::now();
    m_formatConverter = FormatConverterFactory::Create();
}

DeckLinkCaptureDevice::~DeckLinkCaptureDevice() {
    StopCapture();
}

bool DeckLinkCaptureDevice::Initialize(const std::string& deviceName) {
    try {
        std::cout << "[DeckLink] Initializing device: " << deviceName << std::endl;
        
        // Create DeckLink iterator
        CComPtr<IDeckLinkIterator> deckLinkIterator;
        HRESULT result = CoCreateInstance(CLSID_CDeckLinkIterator, NULL, CLSCTX_ALL, 
                                         IID_IDeckLinkIterator, (void**)&deckLinkIterator);
        
        if (result != S_OK || !deckLinkIterator) {
            std::cerr << "[DeckLink] Failed to create iterator. Is DeckLink driver installed?" << std::endl;
            return false;
        }
        
        // Find the requested device
        IDeckLink* deckLink = nullptr;
        bool found = false;
        
        while (deckLinkIterator->Next(&deckLink) == S_OK) {
            BSTR displayName = nullptr;
            
            if (deckLink->GetDisplayName(&displayName) == S_OK) {
                std::string name = BSTRToString(displayName);
                SysFreeString(displayName);
                
                if (name == deviceName) {
                    found = true;
                    m_device.Attach(deckLink);
                    break;
                }
            }
            
            deckLink->Release();
        }
        
        if (!found) {
            std::cerr << "[DeckLink] Device not found: " << deviceName << std::endl;
            return false;
        }
        
        return InitializeFromDevice(m_device, deviceName);
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in Initialize: " << e.what() << std::endl;
        return false;
    }
}

bool DeckLinkCaptureDevice::InitializeFromDevice(IDeckLink* device, const std::string& deviceName) {
    try {
        m_deviceInfo.name = deviceName;
        
        // Get serial number for reconnection
        m_deviceInfo.serialNumber = GetDeviceSerialNumber();
        if (!m_deviceInfo.serialNumber.empty()) {
            std::cout << "[DeckLink] Device serial: " << m_deviceInfo.serialNumber << std::endl;
        }
        
        // Get input interface
        HRESULT result = device->QueryInterface(IID_IDeckLinkInput, (void**)&m_deckLinkInput);
        if (result != S_OK) {
            std::cerr << "[DeckLink] Device does not support input" << std::endl;
            return false;
        }
        
        // Get attributes interface
        device->QueryInterface(IID_IDeckLinkProfileAttributes, (void**)&m_attributes);
        
        // Create callback
        m_callback = new CaptureCallback(this);
        
        // Set callback
        result = m_deckLinkInput->SetCallback(m_callback);
        if (result != S_OK) {
            std::cerr << "[DeckLink] Failed to set callback" << std::endl;
            m_callback->Release();
            m_callback = nullptr;
            return false;
        }
        
        std::cout << "[DeckLink] Device initialized successfully" << std::endl;
        return true;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in InitializeFromDevice: " << e.what() << std::endl;
        return false;
    }
}

bool DeckLinkCaptureDevice::FindBestDisplayMode() {
    CComPtr<IDeckLinkDisplayModeIterator> displayModeIterator;
    HRESULT result = m_deckLinkInput->GetDisplayModeIterator(&displayModeIterator);
    if (result != S_OK) {
        return false;
    }
    
    CComPtr<IDeckLinkDisplayMode> displayMode;
    BMDDisplayMode selectedMode = bmdModeUnknown;
    
    // Try to find 1080p60 mode first (from reference)
    while (displayModeIterator->Next(&displayMode) == S_OK) {
        BMDDisplayMode mode = displayMode->GetDisplayMode();
        if (mode == bmdModeHD1080p6000 || mode == bmdModeHD1080p5994) {
            selectedMode = mode;
            m_width = displayMode->GetWidth();
            m_height = displayMode->GetHeight();
            displayMode->GetFrameRate(&m_frameDuration, &m_frameTimescale);
            std::cout << "[DeckLink] Found Full HD 60fps mode" << std::endl;
            break;
        }
        if (selectedMode == bmdModeUnknown) {
            selectedMode = mode;
            m_width = displayMode->GetWidth();
            m_height = displayMode->GetHeight();
            displayMode->GetFrameRate(&m_frameDuration, &m_frameTimescale);
        }
        displayMode.Release();
    }
    
    if (selectedMode == bmdModeUnknown) {
        return false;
    }
    
    m_displayMode = selectedMode;
    return true;
}

bool DeckLinkCaptureDevice::EnableVideoInput() {
    // Enable video input with format detection (from reference)
    HRESULT result = m_deckLinkInput->EnableVideoInput(
        m_displayMode, 
        m_pixelFormat,
        bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection
    );
    
    if (result != S_OK) {
        std::cerr << "[DeckLink] Failed to enable video input" << std::endl;
        return false;
    }
    
    return true;
}

bool DeckLinkCaptureDevice::StartCapture() {
    if (m_isCapturing) {
        return true;
    }
    
    try {
        std::cout << "[DeckLink] Starting capture..." << std::endl;
        
        // Find best display mode
        if (!FindBestDisplayMode()) {
            std::cerr << "[DeckLink] No display modes available" << std::endl;
            return false;
        }
        
        // Enable video input
        if (!EnableVideoInput()) {
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
        ResetStatistics();
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
    
    // Stop streams
    if (m_deckLinkInput) {
        m_deckLinkInput->StopStreams();
        m_deckLinkInput->DisableVideoInput();
        
        if (m_callback) {
            m_deckLinkInput->SetCallback(nullptr);
            m_callback->Release();
            m_callback = nullptr;
        }
    }
    
    // Clear frame queue
    {
        std::lock_guard<std::mutex> lock(m_queueMutex);
        m_frameQueue.clear();
    }
    m_frameAvailable.notify_all();
    
    // Log final statistics
    LogFrameStatistics();
    std::cout << "[DeckLink] Capture stopped. Total frames: " << m_frameCount.load() << std::endl;
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
            m_droppedFrames++;
            return;
        }
        
        // Prepare buffer for CPU read access
        result = videoBuffer->StartAccess(bmdBufferAccessRead);
        if (result != S_OK) {
            m_droppedFrames++;
            return;
        }
        
        // Get pointer to frame data
        void* frameBytes = nullptr;
        result = videoBuffer->GetBytes(&frameBytes);
        if (result != S_OK) {
            videoBuffer->EndAccess(bmdBufferAccessRead);
            m_droppedFrames++;
            return;
        }
        
        // Calculate frame size
        size_t frameSize = videoFrame->GetRowBytes() * frameHeight;
        
        // Queue frame
        {
            std::lock_guard<std::mutex> lock(m_queueMutex);
            
            // Drop oldest frame if queue is full
            if (m_frameQueue.size() >= MAX_QUEUE_SIZE) {
                m_frameQueue.pop_front();
                m_droppedFrames++;
            }
            
            // Add new frame
            QueuedFrame frame;
            frame.data.resize(frameSize);
            memcpy(frame.data.data(), frameBytes, frameSize);
            frame.width = frameWidth;
            frame.height = frameHeight;
            frame.pixelFormat = m_pixelFormat;
            frame.timestamp = std::chrono::steady_clock::now();
            
            m_frameQueue.push_back(std::move(frame));
        }
        
        // End buffer access
        videoBuffer->EndAccess(bmdBufferAccessRead);
        
        // Update statistics
        m_frameCount++;
        
        // Store timestamp for rolling average (from reference)
        {
            std::lock_guard<std::mutex> lock(m_statsMutex);
            m_frameHistory.push_back({static_cast<int>(m_frameCount.load()), 
                                     std::chrono::high_resolution_clock::now()});
            
            // Remove old entries (keep 60 seconds)
            auto cutoffTime = std::chrono::high_resolution_clock::now() - std::chrono::seconds(60);
            while (!m_frameHistory.empty() && m_frameHistory.front().timestamp < cutoffTime) {
                m_frameHistory.pop_front();
            }
        }
        
        // Notify waiting threads
        m_frameAvailable.notify_one();
        
        // Log statistics every 60 frames
        if (m_frameCount % 60 == 0) {
            LogFrameStatistics();
        }
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in OnFrameArrived: " << e.what() << std::endl;
        m_droppedFrames++;
    }
}

void DeckLinkCaptureDevice::OnFormatChanged(BMDVideoInputFormatChangedEvents events,
                                           IDeckLinkDisplayMode* newMode,
                                           BMDDetectedVideoInputFormatFlags flags) {
    try {
        if (!newMode) {
            return;
        }
        
        // Get new format details
        BMDDisplayMode newDisplayMode = newMode->GetDisplayMode();
        int newWidth = newMode->GetWidth();
        int newHeight = newMode->GetHeight();
        
        // Determine new pixel format
        BMDPixelFormat newPixelFormat = m_pixelFormat;
        if (flags & bmdDetectedVideoInputRGB444) {
            newPixelFormat = bmdFormat8BitBGRA;
        } else if (flags & bmdDetectedVideoInputYCbCr422) {
            newPixelFormat = bmdFormat8BitYUV;
        }
        
        // Check if format actually changed
        bool formatChanged = (m_displayMode != newDisplayMode) || 
                           (m_pixelFormat != newPixelFormat);
        
        if (formatChanged) {
            BSTR modeName;
            if (newMode->GetName(&modeName) == S_OK) {
                std::cout << "[DeckLink] Format changed to: " << BSTRToString(modeName) << std::endl;
                SysFreeString(modeName);
            }
            
            // Update format info
            m_width = newWidth;
            m_height = newHeight;
            m_displayMode = newDisplayMode;
            m_pixelFormat = newPixelFormat;
            
            // Get frame rate
            newMode->GetFrameRate(&m_frameDuration, &m_frameTimescale);
            double fps = static_cast<double>(m_frameTimescale) / static_cast<double>(m_frameDuration);
            std::cout << "[DeckLink] New format: " << m_width << "x" << m_height 
                     << " @ " << fps << " fps" << std::endl;
            
            // Handle format change (adapted from reference)
            static bool firstFormatDetection = true;
            if (firstFormatDetection && formatChanged) {
                firstFormatDetection = false;
                std::cout << "[DeckLink] Applying detected format..." << std::endl;
                
                // Restart capture with detected format
                m_deckLinkInput->StopStreams();
                Sleep(50);
                
                // Re-enable with detected format
                HRESULT result = m_deckLinkInput->EnableVideoInput(
                    m_displayMode, 
                    m_pixelFormat,
                    bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection
                );
                
                if (result == S_OK) {
                    result = m_deckLinkInput->StartStreams();
                    if (result == S_OK) {
                        std::cout << "[DeckLink] Capture restarted with detected format" << std::endl;
                    }
                }
            }
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
    
    // Wait for frame with timeout
    std::unique_lock<std::mutex> lock(m_queueMutex);
    if (!m_frameAvailable.wait_for(lock, std::chrono::milliseconds(100),
                                  [this] { return !m_frameQueue.empty() || !m_isCapturing; })) {
        return false;
    }
    
    if (m_frameQueue.empty() || !m_isCapturing) {
        return false;
    }
    
    // Get frame from queue
    QueuedFrame queuedFrame = std::move(m_frameQueue.front());
    m_frameQueue.pop_front();
    lock.unlock();
    
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
    return m_deviceInfo.name;
}

bool DeckLinkCaptureDevice::IsCapturing() const {
    return m_isCapturing;
}

std::vector<std::string> DeckLinkCaptureDevice::GetSupportedFormats() const {
    std::vector<std::string> formats;
    
    if (!m_deckLinkInput) {
        return formats;
    }
    
    CComPtr<IDeckLinkDisplayModeIterator> displayModeIterator;
    HRESULT result = m_deckLinkInput->GetDisplayModeIterator(&displayModeIterator);
    if (result != S_OK) {
        return formats;
    }
    
    CComPtr<IDeckLinkDisplayMode> displayMode;
    while (displayModeIterator->Next(&displayMode) == S_OK) {
        BSTR modeName;
        if (displayMode->GetName(&modeName) == S_OK) {
            formats.push_back(BSTRToString(modeName));
            SysFreeString(modeName);
        }
        displayMode.Release();
    }
    
    return formats;
}

bool DeckLinkCaptureDevice::SetFormat(const std::string& format) {
    // Not implemented - format is auto-detected
    return false;
}

void DeckLinkCaptureDevice::GetStatistics(CaptureStatistics& stats) const {
    stats.capturedFrames = m_frameCount;
    stats.droppedFrames = m_droppedFrames;
    
    auto now = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        now - m_captureStartTime).count();
    
    if (elapsed > 0) {
        stats.averageFPS = static_cast<double>(m_frameCount) / elapsed;
    } else {
        stats.averageFPS = 0.0;
    }
    
    // Calculate rolling average FPS (from reference)
    stats.currentFPS = CalculateRollingFPS();
}

std::string DeckLinkCaptureDevice::GetDeviceSerialNumber() const {
    if (!m_attributes) {
        return "";
    }
    
    BSTR serialNumber;
    if (m_attributes->GetString(BMDDeckLinkSerialPortDeviceName, &serialNumber) == S_OK) {
        std::string serial = BSTRToString(serialNumber);
        SysFreeString(serialNumber);
        return serial;
    }
    
    return "";
}

std::string DeckLinkCaptureDevice::BSTRToString(BSTR bstr) const {
    if (!bstr) return "";
    
    int len = WideCharToMultiByte(CP_UTF8, 0, bstr, -1, NULL, 0, NULL, NULL);
    if (len > 0) {
        std::vector<char> buffer(len);
        WideCharToMultiByte(CP_UTF8, 0, bstr, -1, buffer.data(), len, NULL, NULL);
        return std::string(buffer.data());
    }
    return "";
}

double DeckLinkCaptureDevice::CalculateRollingFPS() const {
    std::lock_guard<std::mutex> lock(m_statsMutex);
    
    if (m_frameHistory.size() < 2) {
        return 0.0;
    }
    
    // Calculate FPS over the last 5 seconds
    auto now = std::chrono::high_resolution_clock::now();
    auto cutoffTime = now - std::chrono::seconds(5);
    
    // Find first frame after cutoff
    auto it = std::find_if(m_frameHistory.begin(), m_frameHistory.end(),
        [cutoffTime](const FrameTimestamp& ft) {
            return ft.timestamp >= cutoffTime;
        });
    
    if (it == m_frameHistory.end() || it == std::prev(m_frameHistory.end())) {
        return 0.0;
    }
    
    auto firstFrame = *it;
    auto lastFrame = m_frameHistory.back();
    
    auto timeDiff = std::chrono::duration_cast<std::chrono::milliseconds>(
        lastFrame.timestamp - firstFrame.timestamp).count();
    
    if (timeDiff <= 0) {
        return 0.0;
    }
    
    int frameDiff = lastFrame.frameNumber - firstFrame.frameNumber;
    return (static_cast<double>(frameDiff) * 1000.0) / timeDiff;
}

void DeckLinkCaptureDevice::LogFrameStatistics() {
    try {
        double rollingFPS = CalculateRollingFPS();
        double expectedFPS = static_cast<double>(m_frameTimescale) / static_cast<double>(m_frameDuration);
        
        std::stringstream ss;
        ss << "[DeckLink] Frames: " << m_frameCount.load();
        
        if (rollingFPS > 0) {
            ss << ", FPS: " << std::fixed << std::setprecision(2) << rollingFPS;
            ss << " (Expected: " << std::fixed << std::setprecision(2) << expectedFPS << ")";
        }
        
        if (m_droppedFrames > 0) {
            ss << ", Dropped: " << m_droppedFrames.load();
        }
        
        std::cout << ss.str() << std::endl;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in LogFrameStatistics: " << e.what() << std::endl;
    }
}

void DeckLinkCaptureDevice::ResetStatistics() {
    m_frameCount = 0;
    m_droppedFrames = 0;
    
    std::lock_guard<std::mutex> lock(m_statsMutex);
    m_frameHistory.clear();
}
