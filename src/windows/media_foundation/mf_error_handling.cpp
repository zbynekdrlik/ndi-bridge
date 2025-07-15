// mf_error_handling.cpp
#include "mf_error_handling.h"
#include <mfapi.h>
#include <iostream>

namespace ndi_bridge {
namespace media_foundation {

thread_local std::string MFErrorHandler::last_error_;

std::string MFErrorHandler::HResultToString(HRESULT hr) {
    _com_error err(hr);
    std::stringstream ss;
    ss << "0x" << std::hex << hr << " - " << err.ErrorMessage();
    return ss.str();
}

bool MFErrorHandler::CheckFailed(const char* operation, HRESULT hr) {
    if (FAILED(hr)) {
        std::stringstream ss;
        ss << operation << " failed: " << HResultToString(hr);
        last_error_ = ss.str();
        std::cerr << last_error_ << std::endl;
        return true;
    }
    return false;
}

bool MFErrorHandler::IsDeviceError(HRESULT hr) {
    return hr == MF_E_DEVICE_INVALIDATED ||
           hr == E_NOINTERFACE ||
           hr == MF_E_HW_MFT_FAILED_START_STREAMING ||
           hr == MF_E_VIDEO_RECORDING_DEVICE_LOCKED;
}

bool MFErrorHandler::RequiresMediaFoundationReinit(HRESULT hr) {
    return hr == MF_E_VIDEO_RECORDING_DEVICE_LOCKED ||
           hr == MF_E_HW_MFT_FAILED_START_STREAMING;
}

void MFErrorHandler::LogError(const std::string& context, HRESULT hr) {
    std::stringstream ss;
    ss << context << ": " << HResultToString(hr);
    last_error_ = ss.str();
    std::cerr << last_error_ << std::endl;
}

std::string MFErrorHandler::GetLastError() {
    return last_error_;
}

// ComInitializer implementation
ComInitializer::ComInitializer() : initialized_(false) {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr) || hr == S_FALSE) {  // S_FALSE means already initialized
        initialized_ = true;
    }
}

ComInitializer::~ComInitializer() {
    if (initialized_) {
        CoUninitialize();
    }
}

// MFInitializer implementation
MFInitializer::MFInitializer() : initialized_(false) {
    HRESULT hr = MFStartup(MF_VERSION);
    if (SUCCEEDED(hr)) {
        initialized_ = true;
    } else {
        MFErrorHandler::LogError("MFStartup failed", hr);
    }
}

MFInitializer::~MFInitializer() {
    if (initialized_) {
        MFShutdown();
    }
}

HRESULT MFInitializer::Reinitialize() {
    if (initialized_) {
        MFShutdown();
        initialized_ = false;
    }
    
    HRESULT hr = MFStartup(MF_VERSION);
    if (SUCCEEDED(hr)) {
        initialized_ = true;
    } else {
        MFErrorHandler::LogError("MFStartup reinit failed", hr);
    }
    return hr;
}

} // namespace media_foundation
} // namespace ndi_bridge
