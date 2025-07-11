// mf_capture_device.h
#pragma once

#include <windows.h>
#include <mfidl.h>
#include <string>
#include <vector>
#include <memory>

namespace ndi_bridge {
namespace media_foundation {

// Device information structure
struct DeviceInfo {
    std::wstring friendly_name;
    std::wstring symbolic_link;
    IMFActivate* activate;  // Not owned, do not release
};

// Media Foundation device management
class MFCaptureDevice {
public:
    MFCaptureDevice();
    ~MFCaptureDevice();
    
    // Enumerate all available capture devices
    HRESULT EnumerateDevices(std::vector<DeviceInfo>& devices);
    
    // Re-enumerate devices and find one by name
    HRESULT FindDeviceByName(const std::wstring& name, IMFActivate** ppActivate);
    
    // Create media source from activate
    HRESULT CreateMediaSource(IMFActivate* pActivate, IMFMediaSource** ppSource);
    
    // Create source reader from media source
    HRESULT CreateSourceReader(IMFMediaSource* pSource, IMFSourceReader** ppReader);
    
    // Create source reader directly from activate
    HRESULT CreateSourceReaderFromActivate(IMFActivate* pActivate, IMFSourceReader** ppReader);
    
    // Configure source reader for video capture
    HRESULT ConfigureSourceReader(IMFSourceReader* pReader);
    
    // Get device friendly name from activate
    static HRESULT GetDeviceFriendlyName(IMFActivate* pActivate, std::wstring& name);
    
    // Release all device activates in a vector
    static void ReleaseDevices(std::vector<IMFActivate*>& devices);
    
private:
    // Internal helper to enumerate devices
    HRESULT EnumerateDevicesInternal(IMFActivate*** pppDevices, UINT32* pCount);
    
    // Cleanup any held resources
    void Cleanup();
    
private:
    IMFAttributes* attributes_;
    std::vector<IMFActivate*> cached_devices_;
};

} // namespace media_foundation
} // namespace ndi_bridge
