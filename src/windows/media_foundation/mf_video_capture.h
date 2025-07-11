// mf_video_capture.h
#pragma once

#include <windows.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <atomic>
#include <thread>
#include <functional>
#include <string>
#include "../../../common/capture_interface.h"

namespace ndi_bridge {
namespace media_foundation {

// Video capture implementation using Media Foundation
class MFVideoCapture {
public:
    MFVideoCapture();
    ~MFVideoCapture();
    
    // Set the frame callback
    void SetFrameCallback(FrameCallback callback);
    
    // Initialize capture with source reader
    HRESULT Initialize(IMFSourceReader* pReader);
    
    // Configure output format (try to set UYVY)
    HRESULT ConfigureOutputFormat();
    
    // Get negotiated format information
    HRESULT GetNegotiatedFormat();
    
    // Start capture loop
    HRESULT StartCapture();
    
    // Stop capture loop
    void StopCapture();
    
    // Check if currently capturing
    bool IsCapturing() const { return is_capturing_; }
    
    // Get format information
    void GetFormatInfo(int& width, int& height, uint32_t& fps_num, uint32_t& fps_den, GUID& subtype) const;
    
    // Get last error
    std::string GetLastError() const { return last_error_; }
    
private:
    // Main capture loop (runs in separate thread)
    void CaptureLoop();
    
    // Process a single sample
    HRESULT ProcessSample(IMFSample* pSample);
    
    // Handle capture errors
    bool HandleCaptureError(HRESULT hr);
    
private:
    IMFSourceReader* source_reader_;  // Not owned
    FrameCallback frame_callback_;
    
    // Format information
    int width_;
    int height_;
    uint32_t fps_numerator_;
    uint32_t fps_denominator_;
    uint32_t interlace_mode_;
    GUID subtype_;
    
    // Capture state
    std::atomic<bool> is_capturing_;
    std::atomic<bool> should_stop_;
    std::thread capture_thread_;
    
    // Frame buffer for format conversion
    std::vector<uint8_t> frame_buffer_;
    
    // Error handling
    std::string last_error_;
    
    // Retry settings
    int retry_delay_ms_;
    static constexpr int kMaxRetryDelayMs = 5000;
    static constexpr int kInitialRetryDelayMs = 1000;
};

} // namespace media_foundation
} // namespace ndi_bridge
