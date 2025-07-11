// mf_capture_device.cpp
#include "mf_capture_device.h"
#include "mf_error_handling.h"
#include <mfreadwrite.h>
#include <iostream>

namespace ndi_bridge {
namespace media_foundation {

MFCaptureDevice::MFCaptureDevice() : attributes_(nullptr) {
}

MFCaptureDevice::~MFCaptureDevice() {
    Cleanup();
}

HRESULT MFCaptureDevice::EnumerateDevices(std::vector<DeviceInfo>& devices) {
    devices.clear();
    Cleanup();
    
    // Create attributes for device enumeration
    HRESULT hr = MFCreateAttributes(&attributes_, 1);
    if (MFErrorHandler::CheckFailed("MFCreateAttributes", hr)) {
        return hr;
    }
    
    // Set attribute to enumerate video capture devices
    hr = attributes_->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, 
                              MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    if (MFErrorHandler::CheckFailed("SetGUID for video capture", hr)) {
        return hr;
    }
    
    // Enumerate devices
    IMFActivate** ppDevices = nullptr;
    UINT32 count = 0;
    hr = EnumerateDevicesInternal(&ppDevices, &count);
    if (FAILED(hr)) {
        return hr;
    }
    
    std::cout << "Found " << count << " capture device(s)." << std::endl;
    
    // Process each device
    for (UINT32 i = 0; i < count; i++) {
        DeviceInfo info;
        info.activate = ppDevices[i];
        
        // Get friendly name
        if (SUCCEEDED(GetDeviceFriendlyName(ppDevices[i], info.friendly_name))) {
            std::wcout << L"Device " << i << L": " << info.friendly_name << std::endl;
            devices.push_back(info);
            cached_devices_.push_back(ppDevices[i]);
        } else {
            ppDevices[i]->Release();
        }
    }
    
    CoTaskMemFree(ppDevices);
    return S_OK;
}

HRESULT MFCaptureDevice::FindDeviceByName(const std::wstring& name, IMFActivate** ppActivate) {
    *ppActivate = nullptr;
    
    std::vector<DeviceInfo> devices;
    HRESULT hr = EnumerateDevices(devices);
    if (FAILED(hr)) {
        return hr;
    }
    
    for (const auto& device : devices) {
        if (device.friendly_name == name) {
            *ppActivate = device.activate;
            (*ppActivate)->AddRef();
            return S_OK;
        }
    }
    
    std::wcerr << L"Device \"" << name << L"\" not found." << std::endl;
    return E_FAIL;
}

HRESULT MFCaptureDevice::CreateMediaSource(IMFActivate* pActivate, IMFMediaSource** ppSource) {
    if (!pActivate || !ppSource) {
        return E_POINTER;
    }
    
    HRESULT hr = pActivate->ActivateObject(IID_PPV_ARGS(ppSource));
    if (MFErrorHandler::CheckFailed("ActivateObject for media source", hr)) {
        return hr;
    }
    
    return S_OK;
}

HRESULT MFCaptureDevice::CreateSourceReader(IMFMediaSource* pSource, IMFSourceReader** ppReader) {
    if (!pSource || !ppReader) {
        return E_POINTER;
    }
    
    HRESULT hr = MFCreateSourceReaderFromMediaSource(pSource, nullptr, ppReader);
    if (MFErrorHandler::CheckFailed("MFCreateSourceReaderFromMediaSource", hr)) {
        return hr;
    }
    
    return S_OK;
}

HRESULT MFCaptureDevice::CreateSourceReaderFromActivate(IMFActivate* pActivate, IMFSourceReader** ppReader) {
    IMFMediaSource* pSource = nullptr;
    HRESULT hr = CreateMediaSource(pActivate, &pSource);
    if (FAILED(hr)) {
        return hr;
    }
    
    hr = CreateSourceReader(pSource, ppReader);
    pSource->Release();
    
    if (SUCCEEDED(hr)) {
        hr = ConfigureSourceReader(*ppReader);
    }
    
    return hr;
}

HRESULT MFCaptureDevice::ConfigureSourceReader(IMFSourceReader* pReader) {
    if (!pReader) {
        return E_POINTER;
    }
    
    // Disable all streams first
    pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
    
    // Enable only the first video stream
    pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
    
    std::cout << "SourceReader configured for video capture." << std::endl;
    return S_OK;
}

HRESULT MFCaptureDevice::GetDeviceFriendlyName(IMFActivate* pActivate, std::wstring& name) {
    WCHAR* wName = nullptr;
    UINT32 wLen = 0;
    
    HRESULT hr = pActivate->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &wName, &wLen);
    if (SUCCEEDED(hr) && wName) {
        name = wName;
        CoTaskMemFree(wName);
    } else {
        name = L"Unknown Device";
    }
    
    return hr;
}

void MFCaptureDevice::ReleaseDevices(std::vector<IMFActivate*>& devices) {
    for (auto* device : devices) {
        if (device) {
            device->Release();
        }
    }
    devices.clear();
}

HRESULT MFCaptureDevice::EnumerateDevicesInternal(IMFActivate*** pppDevices, UINT32* pCount) {
    if (!attributes_) {
        return E_FAIL;
    }
    
    HRESULT hr = MFEnumDeviceSources(attributes_, pppDevices, pCount);
    if (MFErrorHandler::CheckFailed("MFEnumDeviceSources", hr)) {
        return hr;
    }
    
    return S_OK;
}

void MFCaptureDevice::Cleanup() {
    ReleaseDevices(cached_devices_);
    
    if (attributes_) {
        attributes_->Release();
        attributes_ = nullptr;
    }
}

} // namespace media_foundation
} // namespace ndi_bridge
