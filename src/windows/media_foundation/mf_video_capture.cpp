// mf_video_capture.cpp
#include "mf_video_capture.h"
#include "mf_error_handling.h"
#include "mf_format_converter.h"
#include "../../common/logger.h"
#include <chrono>
#include <algorithm>
#include <sstream>

namespace ndi_bridge {
namespace media_foundation {

MFVideoCapture::MFVideoCapture() 
    : source_reader_(nullptr)
    , width_(0)
    , height_(0)
    , fps_numerator_(0)
    , fps_denominator_(0)
    , interlace_mode_(2)  // Default to progressive
    , is_capturing_(false)
    , should_stop_(false)
    , retry_delay_ms_(kInitialRetryDelayMs) {
    subtype_ = GUID_NULL;
}

MFVideoCapture::~MFVideoCapture() {
    StopCapture();
}

void MFVideoCapture::SetFrameCallback(ICaptureDevice::FrameCallback callback) {
    frame_callback_ = callback;
}

HRESULT MFVideoCapture::Initialize(IMFSourceReader* pReader) {
    if (!pReader) {
        return E_POINTER;
    }
    
    source_reader_ = pReader;
    return S_OK;
}

HRESULT MFVideoCapture::ConfigureOutputFormat() {
    if (!source_reader_) {
        return E_FAIL;
    }
    
    // Try to set output to UYVY
    IMFMediaType* pType = nullptr;
    HRESULT hr = MFCreateMediaType(&pType);
    if (FAILED(hr) || !pType) {
        MFErrorHandler::LogError("MFCreateMediaType for UYVY failed", hr);
        return hr;
    }
    
    pType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    pType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_UYVY);
    
    hr = source_reader_->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr, pType);
    pType->Release();
    
    if (FAILED(hr)) {
        Logger::info("Could not set UYVY output. Using device default.");
        // Not a fatal error - we'll convert if needed
    }
    
    return S_OK;  // Always return success - we can convert formats
}

HRESULT MFVideoCapture::GetNegotiatedFormat() {
    if (!source_reader_) {
        return E_FAIL;
    }
    
    IMFMediaType* pOut = nullptr;
    HRESULT hr = source_reader_->GetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &pOut);
    if (MFErrorHandler::CheckFailed("GetCurrentMediaType", hr)) {
        return hr;
    }
    
    // Get frame size
    UINT32 w = 0, h = 0;
    MFGetAttributeSize(pOut, MF_MT_FRAME_SIZE, &w, &h);
    width_ = static_cast<int>(w);
    height_ = static_cast<int>(h);
    
    // Get frame rate
    UINT32 fpsN = 0, fpsD = 0;
    MFGetAttributeRatio(pOut, MF_MT_FRAME_RATE, &fpsN, &fpsD);
    if (fpsD == 0) fpsD = 1;
    fps_numerator_ = fpsN;
    fps_denominator_ = fpsD;
    
    // Get interlace mode
    pOut->GetUINT32(MF_MT_INTERLACE_MODE, &interlace_mode_);
    
    // Get subtype
    pOut->GetGUID(MF_MT_SUBTYPE, &subtype_);
    
    pOut->Release();
    
    // Allocate frame buffer
    size_t buffer_size = FormatConverter::GetUYVYBufferSize(width_, height_);
    frame_buffer_.resize(buffer_size);
    
    double fps = (fps_denominator_ != 0) ? 
        static_cast<double>(fps_numerator_) / static_cast<double>(fps_denominator_) : 0.0;
    
    std::stringstream ss;
    ss << "Negotiated format: " << width_ << "x" << height_ 
       << " @ " << fps << " fps"
       << " (" << FormatConverter::GetFormatName(subtype_) << ")";
    Logger::info(ss.str());
    
    return S_OK;
}

HRESULT MFVideoCapture::StartCapture() {
    if (is_capturing_) {
        return S_OK;
    }
    
    if (!source_reader_ || !frame_callback_) {
        return E_FAIL;
    }
    
    should_stop_ = false;
    is_capturing_ = true;
    
    // Start capture thread
    capture_thread_ = std::thread(&MFVideoCapture::CaptureLoop, this);
    
    return S_OK;
}

void MFVideoCapture::StopCapture() {
    if (!is_capturing_) {
        return;
    }
    
    should_stop_ = true;
    
    if (capture_thread_.joinable()) {
        capture_thread_.join();
    }
    
    is_capturing_ = false;
}

void MFVideoCapture::GetFormatInfo(int& width, int& height, 
                                   uint32_t& fps_num, uint32_t& fps_den, 
                                   GUID& subtype) const {
    width = width_;
    height = height_;
    fps_num = fps_numerator_;
    fps_den = fps_denominator_;
    subtype = subtype_;
}

void MFVideoCapture::CaptureLoop() {
    Logger::info("Capture loop started.");
    
    while (!should_stop_) {
        DWORD streamIndex = 0, flags = 0;
        LONGLONG llTime = 0;
        IMFSample* pSample = nullptr;
        
        HRESULT hr = source_reader_->ReadSample(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 
            0,  // No flags
            &streamIndex, 
            &flags, 
            &llTime, 
            &pSample);
        
        if (FAILED(hr)) {
            if (HandleCaptureError(hr)) {
                if (pSample) pSample->Release();
                break;  // Fatal error or user requested stop
            }
            if (pSample) pSample->Release();
            continue;  // Non-fatal error, continue
        }
        
        // Check for end of stream
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
            Logger::error("End of stream encountered.");
            if (pSample) pSample->Release();
            break;
        }
        
        // Process sample if available
        if (pSample) {
            ProcessSample(pSample);
            pSample->Release();
        } else {
            // No sample available, brief sleep
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
    }
    
    Logger::info("Capture loop ended.");
}

HRESULT MFVideoCapture::ProcessSample(IMFSample* pSample) {
    if (!pSample) {
        return E_POINTER;
    }
    
    IMFMediaBuffer* pBuffer = nullptr;
    HRESULT hr = pSample->ConvertToContiguousBuffer(&pBuffer);
    if (FAILED(hr) || !pBuffer) {
        if (pBuffer) pBuffer->Release();
        return hr;
    }
    
    BYTE* pData = nullptr;
    DWORD cbMax = 0, cbCurrent = 0;
    hr = pBuffer->Lock(&pData, &cbMax, &cbCurrent);
    
    if (SUCCEEDED(hr) && pData) {
        // Get sample timestamp
        LONGLONG llTime = 0;
        pSample->GetSampleTime(&llTime);
        
        // Convert to UYVY if needed
        bool converted = FormatConverter::ConvertToUYVY(
            subtype_, pData, frame_buffer_.data(), width_, height_);
        
        if (converted && frame_callback_) {
            // Prepare format information
            ICaptureDevice::VideoFormat format;
            format.width = width_;
            format.height = height_;
            format.stride = width_ * 2;  // UYVY is 2 bytes per pixel
            format.pixel_format = "UYVY";
            format.fps_numerator = fps_numerator_;
            format.fps_denominator = fps_denominator_;
            
            // Convert timestamp from 100ns units to nanoseconds
            int64_t timestamp_ns = llTime * 100;
            
            // Deliver frame using the ICaptureDevice interface callback signature
            frame_callback_(frame_buffer_.data(), frame_buffer_.size(), timestamp_ns, format);
        }
    }
    
    if (pBuffer) {
        pBuffer->Unlock();
        pBuffer->Release();
    }
    
    return S_OK;
}

bool MFVideoCapture::HandleCaptureError(HRESULT hr) {
    if (MFErrorHandler::IsDeviceError(hr)) {
        last_error_ = MFErrorHandler::HResultToString(hr);
        Logger::error("Device error during capture: " + last_error_);
        
        // Wait before signaling error
        std::this_thread::sleep_for(std::chrono::milliseconds(retry_delay_ms_));
        retry_delay_ms_ = (std::min)(retry_delay_ms_ + 1000, kMaxRetryDelayMs);
        
        return true;  // Fatal error for this capture session
    }
    
    // Log non-fatal error and continue
    MFErrorHandler::LogError("ReadSample error", hr);
    return false;
}

} // namespace media_foundation
} // namespace ndi_bridge
