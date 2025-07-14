// DeckLinkDeviceEnumerator.h
#pragma once

#include <vector>
#include <string>
#include <memory>
#include <atlbase.h>

struct IDeckLink;

class DeckLinkDeviceEnumerator {
public:
    struct DeviceInfo {
        std::string name;
        std::string serialNumber;
        int index;
        CComPtr<IDeckLink> device;
    };

    DeckLinkDeviceEnumerator();
    ~DeckLinkDeviceEnumerator();

    // Enumerate all available DeckLink devices
    bool EnumerateDevices();
    
    // Get list of device names
    std::vector<std::string> GetDeviceNames() const;
    
    // Get device info by index
    bool GetDeviceInfo(int index, DeviceInfo& info) const;
    
    // Find device by name or serial number
    int FindDevice(const std::string& nameOrSerial) const;
    
    // Get device count
    int GetDeviceCount() const { return static_cast<int>(m_devices.size()); }
    
    // Get device by index
    IDeckLink* GetDevice(int index) const;

private:
    std::vector<DeviceInfo> m_devices;
    
    std::string GetDeviceSerialNumber(IDeckLink* device) const;
    std::string BSTRToString(BSTR bstr) const;
};
