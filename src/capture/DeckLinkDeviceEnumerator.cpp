// DeckLinkDeviceEnumerator.cpp
#include "DeckLinkDeviceEnumerator.h"
#include <iostream>
#include <algorithm>

// DeckLink SDK includes
#include "DeckLinkAPI_h.h"

// Include the DeckLinkAPI_i.c file for GUIDs
extern "C" {
    #include "DeckLinkAPI_i.c"
}

DeckLinkDeviceEnumerator::DeckLinkDeviceEnumerator() {
}

DeckLinkDeviceEnumerator::~DeckLinkDeviceEnumerator() {
    m_devices.clear();
}

bool DeckLinkDeviceEnumerator::EnumerateDevices() {
    m_devices.clear();
    
    std::cout << "[DeckLink] Enumerating devices..." << std::endl;
    
    // Create DeckLink iterator with retry (from reference)
    CComPtr<IDeckLinkIterator> deckLinkIterator;
    HRESULT result;
    int retryCount = 3;
    
    while (retryCount > 0) {
        result = CoCreateInstance(CLSID_CDeckLinkIterator, NULL, CLSCTX_ALL, 
                                 IID_IDeckLinkIterator, (void**)&deckLinkIterator);
        
        if (result == S_OK && deckLinkIterator != nullptr) {
            break;
        }
        
        retryCount--;
        if (retryCount > 0) {
            std::cout << "[DeckLink] Failed to create iterator, retrying..." << std::endl;
            Sleep(1000);
        }
    }
    
    if (result != S_OK || deckLinkIterator == nullptr) {
        std::cerr << "[DeckLink] Failed to create iterator. Is DeckLink driver installed?" << std::endl;
        return false;
    }
    
    // Enumerate all DeckLink devices
    IDeckLink* deckLink = nullptr;
    int deviceIndex = 0;
    
    while (deckLinkIterator->Next(&deckLink) == S_OK) {
        // Check for input capability first
        CComPtr<IDeckLinkInput> deckLinkInput;
        if (deckLink->QueryInterface(IID_IDeckLinkInput, (void**)&deckLinkInput) == S_OK) {
            DeviceInfo info;
            info.index = deviceIndex;
            
            // Get display name
            BSTR deviceName = nullptr;
            if (deckLink->GetDisplayName(&deviceName) == S_OK) {
                info.name = BSTRToString(deviceName);
                SysFreeString(deviceName);
            }
            
            // Get serial number
            info.serialNumber = GetDeviceSerialNumber(deckLink);
            
            // Store device
            info.device.Attach(deckLink);
            m_devices.push_back(info);
            
            std::cout << "[DeckLink] Found device [" << deviceIndex << "]: \"" << info.name << "\"";
            if (!info.serialNumber.empty()) {
                std::cout << " (Serial: " << info.serialNumber << ")";
            }
            std::cout << std::endl;
            
            deviceIndex++;
        } else {
            // Device doesn't support input
            deckLink->Release();
        }
    }
    
    if (m_devices.empty()) {
        std::cout << "[DeckLink] No input devices found" << std::endl;
        return false;
    }
    
    std::cout << "[DeckLink] Found " << m_devices.size() << " input device(s)" << std::endl;
    return true;
}

std::vector<std::string> DeckLinkDeviceEnumerator::GetDeviceNames() const {
    std::vector<std::string> names;
    names.reserve(m_devices.size());
    
    for (const auto& device : m_devices) {
        names.push_back(device.name);
    }
    
    return names;
}

bool DeckLinkDeviceEnumerator::GetDeviceInfo(int index, DeviceInfo& info) const {
    if (index < 0 || index >= static_cast<int>(m_devices.size())) {
        return false;
    }
    
    info = m_devices[index];
    return true;
}

int DeckLinkDeviceEnumerator::FindDevice(const std::string& nameOrSerial) const {
    // First try to find by name
    for (size_t i = 0; i < m_devices.size(); i++) {
        if (m_devices[i].name == nameOrSerial) {
            return static_cast<int>(i);
        }
    }
    
    // Then try by serial number
    for (size_t i = 0; i < m_devices.size(); i++) {
        if (m_devices[i].serialNumber == nameOrSerial) {
            return static_cast<int>(i);
        }
    }
    
    return -1;
}

IDeckLink* DeckLinkDeviceEnumerator::GetDevice(int index) const {
    if (index < 0 || index >= static_cast<int>(m_devices.size())) {
        return nullptr;
    }
    
    return m_devices[index].device;
}

std::string DeckLinkDeviceEnumerator::GetDeviceSerialNumber(IDeckLink* device) const {
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

std::string DeckLinkDeviceEnumerator::BSTRToString(BSTR bstr) const {
    if (!bstr) return "";
    
    int len = WideCharToMultiByte(CP_UTF8, 0, bstr, -1, NULL, 0, NULL, NULL);
    if (len > 0) {
        std::vector<char> buffer(len);
        WideCharToMultiByte(CP_UTF8, 0, bstr, -1, buffer.data(), len, NULL, NULL);
        return std::string(buffer.data());
    }
    return "";
}
