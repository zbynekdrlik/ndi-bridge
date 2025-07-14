/*
 * ndi_connect_robust.cpp - Ultra-robust, high-performance Windows C++ console application
 * Captures video from Blackmagic DeckLink devices and streams via NDI 6
 * Features automatic error recovery, device reconnection, and continuous operation
 * 
 * Build Instructions for Visual Studio 2019:
 * 1. Create new Console Application (x64)
 * 2. Copy from DeckLink SDK to project folder:
 *    - DeckLinkAPI_h.h
 *    - DeckLinkAPI_i.c
 * 3. Add DeckLinkAPI_i.c to project
 * 4. Download and install NDI SDK 6
 * 5. Add NDI include and lib paths to project settings
 * 6. Link against: Processing.NDI.Lib.x64.lib
 * 7. Build in Release mode for optimal performance
 */

#pragma warning(push)
#pragma warning(disable: 26495) // Disable uninitialized member warnings for external structures

#include <windows.h>
#include <comutil.h>
#include <iostream>
#include <string>
#include <vector>
#include <iomanip>
#include <atlbase.h>
#include <chrono>
#include <thread>
#include <atomic>
#include <cstring>
#include <sstream>
#include <deque>
#include <mutex>
#include <condition_variable>
#include <exception>
#include <csignal>

// DeckLink API includes
#include "DeckLinkAPI_h.h"

// NDI SDK includes
#include <Processing.NDI.Lib.h>

#pragma comment(lib, "comsuppw.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

// Include the DeckLinkAPI_i.c file for GUIDs
extern "C" {
    #include "DeckLinkAPI_i.c"
}

#pragma warning(pop)

// Console colors for structured logging
#define COLOR_RESET     "\033[0m"
#define COLOR_RED       "\033[31m"
#define COLOR_GREEN     "\033[32m"
#define COLOR_YELLOW    "\033[33m"
#define COLOR_BLUE      "\033[34m"
#define COLOR_MAGENTA   "\033[35m"
#define COLOR_CYAN      "\033[36m"
#define COLOR_WHITE     "\033[37m"

// Forward declarations
std::string GetTimestamp();
void LogMessage(const std::string& level, const std::string& color, const std::string& message);

// Logging macros with timestamp
#define LOG_ERROR(msg)   LogMessage("ERROR", COLOR_RED, msg)
#define LOG_WARN(msg)    LogMessage("WARN", COLOR_YELLOW, msg)
#define LOG_INFO(msg)    LogMessage("INFO", COLOR_GREEN, msg)
#define LOG_DEBUG(msg)   LogMessage("DEBUG", COLOR_CYAN, msg)

// Error recovery settings
constexpr int RECONNECT_DELAY_MS = 5000;           // 5 seconds between reconnect attempts
constexpr int DEVICE_POLL_INTERVAL_MS = 2000;      // 2 seconds for device polling
constexpr int CAPTURE_HEALTH_CHECK_MS = 3000;      // 3 seconds for capture health check
constexpr int MAX_CONSECUTIVE_ERRORS = 10;         // Max errors before restart
constexpr int FRAME_TIMEOUT_MS = 5000;             // 5 seconds without frames triggers restart

// Global variables
std::atomic<bool> g_applicationRunning(true);
std::atomic<bool> g_captureRunning(false);
std::atomic<bool> g_shouldRestart(false);
std::atomic<int> g_errorCount(0);
std::atomic<std::chrono::steady_clock::time_point> g_lastFrameTime;
std::mutex g_captureMutex;
std::condition_variable g_captureCV;
NDIlib_send_instance_t g_ndiSender = nullptr;
std::mutex g_ndiMutex;

// Device information for reconnection
struct DeviceInfo {
    std::string name;
    std::string serialNumber;
    int originalIndex;
};
DeviceInfo g_targetDevice;

// Signal handler for graceful shutdown
void SignalHandler(int signal) {
    LOG_WARN("Received signal " + std::to_string(signal) + ", shutting down gracefully...");
    g_applicationRunning = false;
    g_captureRunning = false;
    g_captureCV.notify_all();
}

// Get current timestamp string
std::string GetTimestamp() {
    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
    
    struct tm timeinfo;
    localtime_s(&timeinfo, &in_time_t);
    
    std::stringstream ss;
    ss << std::put_time(&timeinfo, "%Y-%m-%d %H:%M:%S");
    ss << '.' << std::setfill('0') << std::setw(3) << ms.count();
    return ss.str();
}

// Thread-safe logging function
void LogMessage(const std::string& level, const std::string& color, const std::string& message) {
    static std::mutex logMutex;
    std::lock_guard<std::mutex> lock(logMutex);
    std::cout << "[" << GetTimestamp() << "] " << color << "[" << level << "]" << COLOR_RESET << " " << message << std::endl;
}

// Convert BSTR to std::string
std::string BSTRToString(BSTR bstr) {
    if (!bstr) return "";
    
    int len = WideCharToMultiByte(CP_UTF8, 0, bstr, -1, NULL, 0, NULL, NULL);
    if (len > 0) {
        std::vector<char> buffer(len);
        WideCharToMultiByte(CP_UTF8, 0, bstr, -1, buffer.data(), len, NULL, NULL);
        return std::string(buffer.data());
    }
    return "";
}

// Exception-safe COM initialization
class COMInitializer {
public:
    COMInitializer() {
        HRESULT result = CoInitializeEx(NULL, COINIT_MULTITHREADED);
        m_initialized = SUCCEEDED(result);
        if (!m_initialized) {
            throw std::runtime_error("Failed to initialize COM");
        }
    }
    
    ~COMInitializer() {
        if (m_initialized) {
            CoUninitialize();
        }
    }
    
private:
    bool m_initialized;
};

// Robust capture callback class with error handling
class CaptureCallback : public IDeckLinkInputCallback {
private:
    std::atomic<ULONG> m_refCount;
    IDeckLinkInput* m_deckLinkInput;
    std::atomic<int> m_frameCount;
    BMDPixelFormat m_pixelFormat;
    int m_width;
    int m_height;
    BMDTimeValue m_frameDuration;
    BMDTimeScale m_frameTimescale;
    std::chrono::high_resolution_clock::time_point m_startTime;
    std::mutex m_frameMutex;
    
    // For rolling average calculation
    struct FrameTimestamp {
        int frameNumber;
        std::chrono::high_resolution_clock::time_point timestamp;
    };
    std::deque<FrameTimestamp> m_frameHistory;
    
public:
    CaptureCallback(IDeckLinkInput* deckLinkInput, BMDPixelFormat pixelFormat)
        : m_refCount(1), m_deckLinkInput(deckLinkInput), m_frameCount(0), 
          m_pixelFormat(pixelFormat), m_width(1920), m_height(1080),
          m_frameDuration(1001), m_frameTimescale(60000) {
        m_startTime = std::chrono::high_resolution_clock::now();
        g_lastFrameTime = std::chrono::steady_clock::now();
        LOG_INFO("Capture callback initialized");
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
        
        try {
            // Only process if we have a valid mode
            if (!newMode) {
                return S_OK;
            }
            
            // Get the new format details
            BMDDisplayMode newDisplayMode = newMode->GetDisplayMode();
            int newWidth = newMode->GetWidth();
            int newHeight = newMode->GetHeight();
            
            // Determine new pixel format
            BMDPixelFormat newPixelFormat = m_pixelFormat;
            if (detectedSignalFlags & bmdDetectedVideoInputRGB444) {
                newPixelFormat = bmdFormat8BitBGRA;
            } else if (detectedSignalFlags & bmdDetectedVideoInputYCbCr422) {
                newPixelFormat = bmdFormat8BitYUV;
            }
            
            // Check if format actually changed
            static BMDDisplayMode currentMode = bmdModeUnknown;
            static BMDPixelFormat currentPixelFormat = bmdFormatUnspecified;
            
            bool formatChanged = (currentMode != newDisplayMode) || (currentPixelFormat != newPixelFormat);
            
            if (formatChanged) {
                BSTR modeName;
                if (newMode->GetName(&modeName) == S_OK) {
                    LOG_INFO("Video format changed to: " + BSTRToString(modeName));
                    SysFreeString(modeName);
                }
                
                // Update dimensions
                {
                    std::lock_guard<std::mutex> lock(m_frameMutex);
                    m_width = newWidth;
                    m_height = newHeight;
                }
                LOG_INFO("Dimensions: " + std::to_string(m_width) + "x" + std::to_string(m_height));
                
                // Get frame rate
                newMode->GetFrameRate(&m_frameDuration, &m_frameTimescale);
                double fps = (double)m_frameTimescale / (double)m_frameDuration;
                LOG_INFO("Frame rate: " + std::to_string(fps) + " fps");
                
                // Update pixel format
                m_pixelFormat = newPixelFormat;
                
                // Remember current format
                currentMode = newDisplayMode;
                currentPixelFormat = newPixelFormat;
                
                // Handle format change
                static bool firstFormatDetection = true;
                if (firstFormatDetection && formatChanged) {
                    firstFormatDetection = false;
                    LOG_INFO("Initial format detection complete - applying detected format");
                    
                    // We need to restart capture with the detected format
                    m_deckLinkInput->StopStreams();
                    Sleep(50);
                    
                    // Re-enable with detected format
                    HRESULT result = m_deckLinkInput->EnableVideoInput(newDisplayMode, m_pixelFormat, 
                                                     bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection);
                    if (result != S_OK) {
                        LOG_ERROR("Failed to re-enable video input with detected format");
                        g_errorCount++;
                        return S_OK;
                    }
                    
                    // Restart streams
                    result = m_deckLinkInput->StartStreams();
                    if (result != S_OK) {
                        LOG_ERROR("Failed to restart streams");
                        g_errorCount++;
                        return S_OK;
                    }
                    
                    LOG_INFO("Capture restarted with detected format");
                }
            }
        }
        catch (const std::exception& e) {
            LOG_ERROR("Exception in VideoInputFormatChanged: " + std::string(e.what()));
            g_errorCount++;
        }
        
        return S_OK;
    }
    
    virtual HRESULT STDMETHODCALLTYPE VideoInputFrameArrived(
        IDeckLinkVideoInputFrame* videoFrame,
        IDeckLinkAudioInputPacket* audioPacket) {
        
        try {
            // Update last frame time
            g_lastFrameTime = std::chrono::steady_clock::now();
            
            static int totalFrames = 0;
            totalFrames++;
            
            if (!videoFrame) {
                return S_OK;
            }
            
            // Check for valid frame
            BMDFrameFlags flags = videoFrame->GetFlags();
            if (flags & bmdFrameHasNoInputSource) {
                // No input signal - log periodically
                static auto lastNoSignalLog = std::chrono::steady_clock::now();
                auto now = std::chrono::steady_clock::now();
                if (std::chrono::duration_cast<std::chrono::seconds>(now - lastNoSignalLog).count() >= 10) {
                    LOG_WARN("No input signal on device (logged every 10s)");
                    lastNoSignalLog = now;
                }
                return S_OK;
            }
            
            // Log when we start receiving valid frames
            static bool firstValidFrame = true;
            if (firstValidFrame) {
                LOG_INFO("Started receiving valid frames");
                firstValidFrame = false;
                g_errorCount = 0; // Reset error count on successful frame
            }
            
            // Get actual frame dimensions
            long frameWidth = videoFrame->GetWidth();
            long frameHeight = videoFrame->GetHeight();
            
            // Update dimensions if they changed
            {
                std::lock_guard<std::mutex> lock(m_frameMutex);
                if (frameWidth != m_width || frameHeight != m_height) {
                    m_width = frameWidth;
                    m_height = frameHeight;
                    LOG_INFO("Frame dimensions updated: " + std::to_string(m_width) + "x" + std::to_string(m_height));
                }
            }
            
            // Process and send frame via NDI
            if (!ProcessAndSendFrame(videoFrame)) {
                g_errorCount++;
            } else {
                // Reset error count on successful processing
                if (g_errorCount > 0) {
                    g_errorCount--;
                }
            }
            
            m_frameCount++;
            
            // Store frame timestamp for rolling average
            auto now = std::chrono::high_resolution_clock::now();
            {
                std::lock_guard<std::mutex> lock(m_frameMutex);
                m_frameHistory.push_back({m_frameCount.load(), now});
                
                // Remove frames older than 60 seconds from history
                auto cutoffTime = now - std::chrono::seconds(60);
                while (!m_frameHistory.empty() && m_frameHistory.front().timestamp < cutoffTime) {
                    m_frameHistory.pop_front();
                }
            }
            
            // Log frame info every 60 frames
            if (m_frameCount % 60 == 0) {
                LogFrameStatistics();
            }
            
            // Check for excessive errors
            if (g_errorCount > MAX_CONSECUTIVE_ERRORS) {
                LOG_ERROR("Too many consecutive errors, triggering restart");
                g_shouldRestart = true;
            }
        }
        catch (const std::exception& e) {
            LOG_ERROR("Exception in VideoInputFrameArrived: " + std::string(e.what()));
            g_errorCount++;
        }
        
        return S_OK;
    }
    
    int GetFrameCount() const { return m_frameCount.load(); }
    
private:
    bool ProcessAndSendFrame(IDeckLinkVideoInputFrame* videoFrame) {
        try {
            // Get the video buffer interface
            CComPtr<IDeckLinkVideoBuffer> videoBuffer;
            HRESULT result = videoFrame->QueryInterface(IID_IDeckLinkVideoBuffer, (void**)&videoBuffer);
            if (result != S_OK) {
                LOG_ERROR("Failed to get video buffer interface");
                return false;
            }
            
            // Prepare buffer for CPU read access
            result = videoBuffer->StartAccess(bmdBufferAccessRead);
            if (result != S_OK) {
                LOG_ERROR("Failed to start buffer access");
                return false;
            }
            
            // Get pointer to frame data
            void* frameBytes = nullptr;
            result = videoBuffer->GetBytes(&frameBytes);
            if (result != S_OK) {
                LOG_ERROR("Failed to get frame bytes");
                videoBuffer->EndAccess(bmdBufferAccessRead);
                return false;
            }
            
            // Prepare NDI frame
            NDIlib_video_frame_v2_t ndiFrame = {};
            {
                std::lock_guard<std::mutex> lock(m_frameMutex);
                ndiFrame.xres = m_width;
                ndiFrame.yres = m_height;
            }
            ndiFrame.frame_rate_N = (int)m_frameTimescale;
            ndiFrame.frame_rate_D = (int)m_frameDuration;
            ndiFrame.timecode = NDIlib_send_timecode_synthesize;
            
            // Handle different pixel formats
            if (m_pixelFormat == bmdFormat8BitBGRA) {
                ndiFrame.FourCC = NDIlib_FourCC_type_BGRA;
                ndiFrame.p_data = (uint8_t*)frameBytes;
                ndiFrame.line_stride_in_bytes = videoFrame->GetRowBytes();
            } else if (m_pixelFormat == bmdFormat8BitYUV) {
                ndiFrame.FourCC = NDIlib_FourCC_type_UYVY;
                ndiFrame.p_data = (uint8_t*)frameBytes;
                ndiFrame.line_stride_in_bytes = videoFrame->GetRowBytes();
            } else {
                static bool warnLogged = false;
                if (!warnLogged) {
                    LOG_WARN("Unsupported pixel format: " + std::to_string(m_pixelFormat));
                    warnLogged = true;
                }
                videoBuffer->EndAccess(bmdBufferAccessRead);
                return false;
            }
            
            // Send frame via NDI (thread-safe)
            {
                std::lock_guard<std::mutex> lock(g_ndiMutex);
                if (g_ndiSender) {
                    NDIlib_send_send_video_v2(g_ndiSender, &ndiFrame);
                }
            }
            
            // End buffer access
            videoBuffer->EndAccess(bmdBufferAccessRead);
            return true;
        }
        catch (const std::exception& e) {
            LOG_ERROR("Exception in ProcessAndSendFrame: " + std::string(e.what()));
            return false;
        }
    }
    
    void LogFrameStatistics() {
        try {
            auto now = std::chrono::high_resolution_clock::now();
            
            // Calculate 1-minute rolling average FPS
            double rollingAvgFps = 0.0;
            {
                std::lock_guard<std::mutex> lock(m_frameMutex);
                if (m_frameHistory.size() > 1) {
                    auto oldestFrame = m_frameHistory.front();
                    auto newestFrame = m_frameHistory.back();
                    auto timeDiff = std::chrono::duration_cast<std::chrono::milliseconds>(
                        newestFrame.timestamp - oldestFrame.timestamp).count();
                    int frameDiff = newestFrame.frameNumber - oldestFrame.frameNumber;
                    if (timeDiff > 0) {
                        rollingAvgFps = (double)frameDiff / (timeDiff / 1000.0);
                    }
                }
            }
            
            // Calculate instantaneous FPS
            static std::chrono::high_resolution_clock::time_point lastLogTime = m_startTime;
            auto recentDuration = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastLogTime).count();
            double instantFps = 60.0 / (recentDuration / 1000.0);
            lastLogTime = now;
            
            std::stringstream ss;
            ss << "Frames: " << m_frameCount.load();
            
            {
                std::lock_guard<std::mutex> lock(m_frameMutex);
                if (m_frameHistory.size() > 60) {
                    ss << ", 1-min avg: " << std::fixed << std::setprecision(2) << rollingAvgFps;
                } else {
                    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - m_startTime).count();
                    if (elapsed < 60) {
                        ss << ", 1-min avg in " << (60 - elapsed) << "s";
                    }
                }
            }
            
            ss << ", Current: " << std::fixed << std::setprecision(2) << instantFps;
            double expectedFps = (double)m_frameTimescale / (double)m_frameDuration;
            ss << " (Expected: " << std::fixed << std::setprecision(2) << expectedFps << ")";
            
            if (g_errorCount > 0) {
                ss << ", Errors: " << g_errorCount.load();
            }
            
            LOG_INFO(ss.str());
        }
        catch (const std::exception& e) {
            LOG_ERROR("Exception in LogFrameStatistics: " + std::string(e.what()));
        }
    }
};

// Get device serial number
std::string GetDeviceSerialNumber(IDeckLink* device) {
    CComPtr<IDeckLinkProfileAttributes> attributes;
    if (device->QueryInterface(IID_IDeckLinkProfileAttributes, (void**)&attributes) == S_OK) {
        BSTR serialNumber;
        if (attributes->GetString(BMDDeckLinkSerialPortDeviceName, &serialNumber) == S_OK) {
            std::string serial = BSTRToString(serialNumber);
            SysFreeString(serialNumber);
            return serial;
        }
    }
    return "";
}

// Enhanced device listing with retry
int ListDeckLinkDevices(std::vector<CComPtr<IDeckLink>>& devices, std::vector<std::string>& deviceNames, bool silent = false) {
    HRESULT result;
    devices.clear();
    deviceNames.clear();
    
    if (!silent) {
        LOG_INFO("Enumerating DeckLink devices...");
    }
    
    // Create DeckLink iterator with retry
    CComPtr<IDeckLinkIterator> deckLinkIterator;
    int retryCount = 3;
    
    while (retryCount > 0) {
        result = CoCreateInstance(CLSID_CDeckLinkIterator, NULL, CLSCTX_ALL, 
                                  IID_IDeckLinkIterator, (void**)&deckLinkIterator);
        
        if (result == S_OK && deckLinkIterator != nullptr) {
            break;
        }
        
        retryCount--;
        if (retryCount > 0) {
            if (!silent) {
                LOG_WARN("Failed to create DeckLink iterator, retrying...");
            }
            Sleep(1000);
        }
    }
    
    if (result != S_OK || deckLinkIterator == nullptr) {
        if (!silent) {
            LOG_ERROR("Failed to create DeckLink iterator after retries");
        }
        return 0;
    }
    
    // Enumerate all DeckLink devices
    IDeckLink* deckLink = nullptr;
    int deviceIndex = 0;
    
    while (deckLinkIterator->Next(&deckLink) == S_OK) {
        BSTR deviceName = nullptr;
        
        // Check for input capability first
        CComPtr<IDeckLinkInput> deckLinkInput;
        if (deckLink->QueryInterface(IID_IDeckLinkInput, (void**)&deckLinkInput) == S_OK) {
            // Get display name
            if (deckLink->GetDisplayName(&deviceName) == S_OK) {
                std::string name = BSTRToString(deviceName);
                if (!silent) {
                    std::cout << "\n" << COLOR_BLUE << "[" << deviceIndex << "] \"" << name << "\"" << COLOR_RESET;
                    
                    // Try to get serial number
                    std::string serial = GetDeviceSerialNumber(deckLink);
                    if (!serial.empty()) {
                        std::cout << " (Serial: " << serial << ")";
                    }
                }
                deviceNames.push_back(name);
                SysFreeString(deviceName);
            }
            
            // Store device
            CComPtr<IDeckLink> device;
            device.Attach(deckLink);
            devices.push_back(device);
            deviceIndex++;
        } else {
            deckLink->Release();
        }
    }
    
    if (!silent) {
        std::cout << std::endl;
        
        if (deviceIndex == 0) {
            LOG_WARN("No DeckLink input devices found.");
        } else {
            LOG_INFO("Found " + std::to_string(deviceIndex) + " DeckLink input device(s)");
        }
    }
    
    return deviceIndex;
}

// Find device by name or serial number
int FindDevice(const std::vector<CComPtr<IDeckLink>>& devices, const std::vector<std::string>& deviceNames, 
               const DeviceInfo& targetDevice) {
    // First try to find by name
    for (size_t i = 0; i < deviceNames.size(); i++) {
        if (deviceNames[i] == targetDevice.name) {
            // If we have a serial number, verify it matches
            if (!targetDevice.serialNumber.empty()) {
                std::string serial = GetDeviceSerialNumber(devices[i]);
                if (serial == targetDevice.serialNumber) {
                    return (int)i;
                }
            } else {
                return (int)i;
            }
        }
    }
    
    // If not found by name, try by serial number only
    if (!targetDevice.serialNumber.empty()) {
        for (size_t i = 0; i < devices.size(); i++) {
            std::string serial = GetDeviceSerialNumber(devices[i]);
            if (serial == targetDevice.serialNumber) {
                LOG_INFO("Device found by serial number (name may have changed)");
                return (int)i;
            }
        }
    }
    
    return -1;
}

// Thread-safe NDI sender creation/destruction
void CreateNDISender(const std::string& ndiName) {
    std::lock_guard<std::mutex> lock(g_ndiMutex);
    
    // Destroy existing sender if any
    if (g_ndiSender) {
        NDIlib_send_destroy(g_ndiSender);
        g_ndiSender = nullptr;
    }
    
    // Create new sender
    NDIlib_send_create_t ndiSendCreate;
    ndiSendCreate.p_ndi_name = ndiName.c_str();
    ndiSendCreate.clock_video = true;
    ndiSendCreate.clock_audio = false;
    
    g_ndiSender = NDIlib_send_create(&ndiSendCreate);
    if (!g_ndiSender) {
        throw std::runtime_error("Failed to create NDI sender");
    }
    
    LOG_INFO("Created NDI sender: " + ndiName);
}

void DestroyNDISender() {
    std::lock_guard<std::mutex> lock(g_ndiMutex);
    
    if (g_ndiSender) {
        NDIlib_send_destroy(g_ndiSender);
        g_ndiSender = nullptr;
        LOG_INFO("Destroyed NDI sender");
    }
}

// Health monitoring thread
void HealthMonitorThread() {
    LOG_INFO("Health monitor thread started");
    
    while (g_applicationRunning) {
        try {
            // Check if capture is supposed to be running
            if (g_captureRunning) {
                // Check for frame timeout
                auto now = std::chrono::steady_clock::now();
                auto lastFrame = g_lastFrameTime.load();
                auto timeSinceLastFrame = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastFrame).count();
                
                if (timeSinceLastFrame > FRAME_TIMEOUT_MS) {
                    LOG_ERROR("Frame timeout detected (" + std::to_string(timeSinceLastFrame) + "ms since last frame)");
                    g_shouldRestart = true;
                    g_captureCV.notify_all();
                }
                
                // Check error count
                if (g_errorCount > MAX_CONSECUTIVE_ERRORS) {
                    LOG_ERROR("Too many errors detected");
                    g_shouldRestart = true;
                    g_captureCV.notify_all();
                }
            }
            
            // Sleep for health check interval
            std::this_thread::sleep_for(std::chrono::milliseconds(CAPTURE_HEALTH_CHECK_MS));
        }
        catch (const std::exception& e) {
            LOG_ERROR("Exception in health monitor: " + std::string(e.what()));
        }
    }
    
    LOG_INFO("Health monitor thread stopped");
}

// Robust capture function with error recovery
bool StartCapture(IDeckLink* device, const std::string& ndiName) {
    CComPtr<IDeckLinkInput> deckLinkInput;
    CaptureCallback* callback = nullptr;
    
    try {
        LOG_INFO("Starting capture...");
        
        // Reset error state
        g_errorCount = 0;
        g_shouldRestart = false;
        
        // Get input interface
        HRESULT result = device->QueryInterface(IID_IDeckLinkInput, (void**)&deckLinkInput);
        if (result != S_OK) {
            throw std::runtime_error("Failed to get input interface");
        }
        
        // Create NDI sender
        CreateNDISender(ndiName);
        
        // Get first available display mode
        CComPtr<IDeckLinkDisplayModeIterator> displayModeIterator;
        result = deckLinkInput->GetDisplayModeIterator(&displayModeIterator);
        if (result != S_OK) {
            throw std::runtime_error("Failed to get display mode iterator");
        }
        
        CComPtr<IDeckLinkDisplayMode> displayMode;
        BMDDisplayMode selectedDisplayMode = bmdModeUnknown;
        
        // Try to find 1080p60 mode
        while (displayModeIterator->Next(&displayMode) == S_OK) {
            BMDDisplayMode mode = displayMode->GetDisplayMode();
            if (mode == bmdModeHD1080p6000 || mode == bmdModeHD1080p5994) {
                selectedDisplayMode = mode;
                LOG_INFO("Found Full HD 60fps mode");
                break;
            }
            if (selectedDisplayMode == bmdModeUnknown) {
                selectedDisplayMode = mode;
            }
            displayMode.Release();
        }
        
        if (selectedDisplayMode == bmdModeUnknown) {
            throw std::runtime_error("No display modes available");
        }
        
        // Create callback
        BMDPixelFormat pixelFormat = bmdFormat8BitYUV;
        callback = new CaptureCallback(deckLinkInput, pixelFormat);
        
        // Set callback
        result = deckLinkInput->SetCallback(callback);
        if (result != S_OK) {
            throw std::runtime_error("Failed to set callback");
        }
        
        // Enable video input with format detection
        result = deckLinkInput->EnableVideoInput(selectedDisplayMode, pixelFormat, 
                                                 bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection);
        if (result != S_OK) {
            throw std::runtime_error("Failed to enable video input");
        }
        
        // Start capture
        result = deckLinkInput->StartStreams();
        if (result != S_OK) {
            throw std::runtime_error("Failed to start streams");
        }
        
        LOG_INFO("Capture started successfully");
        g_captureRunning = true;
        g_lastFrameTime = std::chrono::steady_clock::now();
        
        // Wait for stop signal or restart request
        std::unique_lock<std::mutex> lock(g_captureMutex);
        g_captureCV.wait(lock, []{ return !g_captureRunning || g_shouldRestart || !g_applicationRunning; });
        
        // Log statistics before stopping
        if (callback) {
            LOG_INFO("Capture statistics - Total frames: " + std::to_string(callback->GetFrameCount()));
        }
        
        // Stop capture
        LOG_INFO("Stopping capture...");
        g_captureRunning = false;
        
        deckLinkInput->StopStreams();
        deckLinkInput->DisableVideoInput();
        deckLinkInput->SetCallback(nullptr);
        
        if (callback) {
            callback->Release();
            callback = nullptr;
        }
        
        // Destroy NDI sender
        DestroyNDISender();
        
        LOG_INFO("Capture stopped");
        return true;
    }
    catch (const std::exception& e) {
        LOG_ERROR("Exception in StartCapture: " + std::string(e.what()));
        g_captureRunning = false;
        
        // Cleanup
        if (callback) {
            callback->Release();
        }
        
        if (deckLinkInput) {
            deckLinkInput->StopStreams();
            deckLinkInput->DisableVideoInput();
            deckLinkInput->SetCallback(nullptr);
        }
        
        DestroyNDISender();
        
        return false;
    }
}

// Device reconnection thread
void DeviceReconnectionThread(const std::string& ndiName) {
    LOG_INFO("Device reconnection thread started");
    
    // Wait a bit before starting to ensure main thread has initialized
    std::this_thread::sleep_for(std::chrono::milliseconds(2000));
    
    while (g_applicationRunning) {
        try {
            // Only try to reconnect if capture is not running AND we should restart
            if (!g_captureRunning && g_shouldRestart) {
                LOG_INFO("Attempting device reconnection...");
                
                // Look for the device
                std::vector<CComPtr<IDeckLink>> devices;
                std::vector<std::string> deviceNames;
                int deviceCount = ListDeckLinkDevices(devices, deviceNames, true);
                
                if (deviceCount > 0) {
                    // Try to find our target device
                    int deviceIndex = FindDevice(devices, deviceNames, g_targetDevice);
                    
                    if (deviceIndex >= 0) {
                        LOG_INFO("Target device found: \"" + deviceNames[deviceIndex] + "\"");
                        
                        // Update device info if name changed
                        if (deviceNames[deviceIndex] != g_targetDevice.name) {
                            LOG_INFO("Device name changed from \"" + g_targetDevice.name + 
                                     "\" to \"" + deviceNames[deviceIndex] + "\"");
                            g_targetDevice.name = deviceNames[deviceIndex];
                        }
                        
                        // Try to start capture
                        g_shouldRestart = false;
                        if (StartCapture(devices[deviceIndex], ndiName)) {
                            LOG_INFO("Successfully reconnected and started capture");
                        } else {
                            LOG_ERROR("Failed to start capture after reconnection");
                            g_shouldRestart = true; // Set flag to retry
                        }
                    } else {
                        LOG_WARN("Target device not found, will retry...");
                    }
                } else {
                    LOG_WARN("No DeckLink devices found, will retry...");
                }
            }
            
            // Wait before next attempt
            std::this_thread::sleep_for(std::chrono::milliseconds(DEVICE_POLL_INTERVAL_MS));
        }
        catch (const std::exception& e) {
            LOG_ERROR("Exception in reconnection thread: " + std::string(e.what()));
            std::this_thread::sleep_for(std::chrono::milliseconds(RECONNECT_DELAY_MS));
        }
    }
    
    LOG_INFO("Device reconnection thread stopped");
}

// Print usage information
void PrintUsage(const char* programName) {
    std::cout << "\nUsage:" << std::endl;
    std::cout << "  Interactive mode: " << programName << std::endl;
    std::cout << "  Non-interactive mode: " << programName << " \"<device_name>\" <ndi_name>" << std::endl;
    std::cout << "\nExample:" << std::endl;
    std::cout << "  " << programName << " \"DeckLink Mini Recorder 4K\" my_ndi_stream" << std::endl;
    std::cout << "\nThe application will automatically:" << std::endl;
    std::cout << "  - Reconnect if the device is disconnected" << std::endl;
    std::cout << "  - Recover from errors and continue streaming" << std::endl;
    std::cout << "  - Monitor capture health and restart if needed" << std::endl;
}

int main(int argc, char* argv[]) {
    // Set up signal handlers
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);
    
    // Enable ANSI color codes in Windows console
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
    DWORD dwMode = 0;
    
    // Enable virtual terminal processing for colors
    GetConsoleMode(hOut, &dwMode);
    dwMode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    SetConsoleMode(hOut, dwMode);
    
    // Disable Quick Edit Mode to prevent pausing
    GetConsoleMode(hIn, &dwMode);
    dwMode &= ~ENABLE_QUICK_EDIT_MODE;
    dwMode &= ~ENABLE_MOUSE_INPUT;
    dwMode |= ENABLE_EXTENDED_FLAGS;
    SetConsoleMode(hIn, dwMode);
    
    std::cout << COLOR_CYAN << "============================================" << COLOR_RESET << std::endl;
    std::cout << COLOR_CYAN << "Robust DeckLink to NDI Low-Latency Streamer" << COLOR_RESET << std::endl;
    std::cout << COLOR_CYAN << "============================================" << COLOR_RESET << std::endl;
    std::cout << COLOR_WHITE << "Version 2.0 - Ultra-Robust Edition" << COLOR_RESET << std::endl;
    
    // Check arguments
    bool interactiveMode = (argc == 1);
    std::string deviceName;
    std::string ndiName;
    
    if (argc == 3) {
        deviceName = argv[1];
        ndiName = argv[2];
        LOG_INFO("Non-interactive mode: Device=\"" + deviceName + "\", NDI=\"" + ndiName + "\"");
    } else if (argc != 1) {
        LOG_ERROR("Invalid number of arguments");
        PrintUsage(argv[0]);
        return 1;
    }
    
    try {
        LOG_INFO("Initializing application...");
        
        // Initialize COM
        COMInitializer comInit;
        
        // Initialize NDI
        if (!NDIlib_initialize()) {
            throw std::runtime_error("Failed to initialize NDI SDK");
        }
        
        LOG_INFO("NDI SDK initialized successfully");
        
        // List DeckLink devices
        std::vector<CComPtr<IDeckLink>> devices;
        std::vector<std::string> deviceNames;
        int deviceCount = ListDeckLinkDevices(devices, deviceNames);
        
        if (deviceCount == 0) {
            throw std::runtime_error("No DeckLink devices found");
        }
        
        // Select device
        int selectedDevice = 0;
        
        if (interactiveMode) {
            // Interactive mode
            if (deviceCount > 1) {
                std::cout << "\nSelect device index (0-" << (deviceCount - 1) << "): ";
                std::cin >> selectedDevice;
                std::cin.ignore();
                
                if (selectedDevice < 0 || selectedDevice >= deviceCount) {
                    throw std::runtime_error("Invalid device index");
                }
            }
            
            // Get NDI stream name
            std::cout << "\nEnter NDI stream name: ";
            std::getline(std::cin, ndiName);
            
            if (ndiName.empty()) {
                ndiName = "DeckLink Capture";
                LOG_INFO("Using default NDI name: " + ndiName);
            }
        } else {
            // Non-interactive mode
            bool found = false;
            for (size_t i = 0; i < deviceNames.size(); i++) {
                if (deviceNames[i] == deviceName) {
                    selectedDevice = (int)i;
                    found = true;
                    break;
                }
            }
            
            if (!found) {
                LOG_ERROR("Device not found: \"" + deviceName + "\"");
                std::cout << "\nAvailable devices:" << std::endl;
                for (const auto& name : deviceNames) {
                    std::cout << "  \"" << name << "\"" << std::endl;
                }
                throw std::runtime_error("Device not found");
            }
        }
        
        // Store target device info
        g_targetDevice.name = deviceNames[selectedDevice];
        g_targetDevice.serialNumber = GetDeviceSerialNumber(devices[selectedDevice]);
        g_targetDevice.originalIndex = selectedDevice;
        
        LOG_INFO("Selected device: \"" + g_targetDevice.name + "\"");
        if (!g_targetDevice.serialNumber.empty()) {
            LOG_INFO("Device serial: " + g_targetDevice.serialNumber);
        }
        
        // Start monitoring threads
        std::thread healthThread(HealthMonitorThread);
        std::thread reconnectThread(DeviceReconnectionThread, ndiName);
        
        // Initial capture start
        if (!StartCapture(devices[selectedDevice], ndiName)) {
            LOG_ERROR("Initial capture failed, will retry automatically...");
        }
        
        // Wait for application shutdown in interactive mode
        if (interactiveMode) {
            std::cout << "\n" << COLOR_YELLOW << "Press Enter to stop application..." << COLOR_RESET << std::endl;
            std::cin.get();
            
            LOG_INFO("User requested shutdown");
            g_applicationRunning = false;
            g_captureRunning = false;
            g_captureCV.notify_all();
        } else {
            // In non-interactive mode, wait for signal
            while (g_applicationRunning) {
                std::this_thread::sleep_for(std::chrono::seconds(1));
            }
        }
        
        // Wait for threads to finish
        LOG_INFO("Waiting for threads to finish...");
        if (healthThread.joinable()) {
            healthThread.join();
        }
        if (reconnectThread.joinable()) {
            reconnectThread.join();
        }
        
        // Cleanup
        LOG_INFO("Cleaning up...");
        DestroyNDISender();
        NDIlib_destroy();
        
        LOG_INFO("Application terminated successfully");
        return 0;
    }
    catch (const std::exception& e) {
        LOG_ERROR("Fatal error: " + std::string(e.what()));
        
        // Emergency cleanup
        DestroyNDISender();
        NDIlib_destroy();
        
        return 1;
    }
}
