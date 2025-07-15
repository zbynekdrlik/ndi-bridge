// DeckLinkDeviceInitializer.cpp
#include "capture/DeckLinkDeviceInitializer.h"
#include "capture/DeckLinkCaptureCallback.h"
#include <iostream>
#include <windows.h>
#include <vector>

// DeckLink SDK includes
#include "DeckLinkAPI_h.h"

// Include the DeckLinkAPI_i.c file for GUIDs
extern "C" {
    #include "DeckLinkAPI_i.c"
}

bool DeckLinkDeviceInitializer::Initialize(const std::string& deviceName,
                                          CComPtr<IDeckLink>& device,
                                          CComPtr<IDeckLinkInput>& deckLinkInput,
                                          CComPtr<IDeckLinkProfileAttributes>& attributes,
                                          DeviceInfo& deviceInfo,
                                          DeckLinkCaptureCallback* callback) {
    try {
        std::cout << "[DeckLink] Initializing device: " << deviceName << std::endl;
        
        // Create DeckLink iterator
        CComPtr<IDeckLinkIterator> deckLinkIterator;
        if (!CreateIterator(deckLinkIterator)) {
            return false;
        }
        
        // Find the requested device
        if (!FindDeviceByName(deckLinkIterator, deviceName, device)) {
            std::cerr << "[DeckLink] Device not found: " << deviceName << std::endl;
            return false;
        }
        
        return InitializeFromDevice(device, deviceName, deckLinkInput, 
                                   attributes, deviceInfo, callback);
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in Initialize: " << e.what() << std::endl;
        return false;
    }
}

bool DeckLinkDeviceInitializer::InitializeFromDevice(IDeckLink* device,
                                                    const std::string& deviceName,
                                                    CComPtr<IDeckLinkInput>& deckLinkInput,
                                                    CComPtr<IDeckLinkProfileAttributes>& attributes,
                                                    DeviceInfo& deviceInfo,
                                                    DeckLinkCaptureCallback* callback) {
    try {
        deviceInfo.name = deviceName;
        
        // Get input interface
        HRESULT result = device->QueryInterface(IID_IDeckLinkInput, (void**)&deckLinkInput);
        if (result != S_OK) {
            std::cerr << "[DeckLink] Device does not support input" << std::endl;
            return false;
        }
        
        // Get attributes interface
        device->QueryInterface(IID_IDeckLinkProfileAttributes, (void**)&attributes);
        
        // Get serial number for reconnection
        if (attributes) {
            deviceInfo.serialNumber = GetDeviceSerialNumber(attributes);
            if (!deviceInfo.serialNumber.empty()) {
                std::cout << "[DeckLink] Device serial: " << deviceInfo.serialNumber << std::endl;
            }
        }
        
        // Set callback
        if (callback) {
            result = deckLinkInput->SetCallback(callback);
            if (result != S_OK) {
                std::cerr << "[DeckLink] Failed to set callback" << std::endl;
                return false;
            }
        }
        
        std::cout << "[DeckLink] Device initialized successfully" << std::endl;
        return true;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in InitializeFromDevice: " << e.what() << std::endl;
        return false;
    }
}

std::string DeckLinkDeviceInitializer::GetDeviceSerialNumber(IDeckLinkProfileAttributes* attributes) {
    if (!attributes) {
        return "";
    }
    
    BSTR serialNumber;
    if (attributes->GetString(BMDDeckLinkSerialPortDeviceName, &serialNumber) == S_OK) {
        std::string serial = BSTRToString(serialNumber);
        SysFreeString(serialNumber);
        return serial;
    }
    
    return "";
}

bool DeckLinkDeviceInitializer::CreateIterator(CComPtr<IDeckLinkIterator>& iterator) {
    HRESULT result = CoCreateInstance(CLSID_CDeckLinkIterator, NULL, CLSCTX_ALL, 
                                     IID_IDeckLinkIterator, (void**)&iterator);
    
    if (result != S_OK || !iterator) {
        std::cerr << "[DeckLink] Failed to create iterator. Is DeckLink driver installed?" << std::endl;
        return false;
    }
    
    return true;
}

bool DeckLinkDeviceInitializer::FindDeviceByName(IDeckLinkIterator* iterator,
                                                const std::string& deviceName,
                                                CComPtr<IDeckLink>& device) {
    IDeckLink* deckLink = nullptr;
    
    while (iterator->Next(&deckLink) == S_OK) {
        BSTR displayName = nullptr;
        
        if (deckLink->GetDisplayName(&displayName) == S_OK) {
            std::string name = BSTRToString(displayName);
            SysFreeString(displayName);
            
            if (name == deviceName) {
                device.Attach(deckLink);
                return true;
            }
        }
        
        deckLink->Release();
    }
    
    return false;
}

std::string DeckLinkDeviceInitializer::BSTRToString(BSTR bstr) {
    if (!bstr) return "";
    
    int len = WideCharToMultiByte(CP_UTF8, 0, bstr, -1, NULL, 0, NULL, NULL);
    if (len > 0) {
        std::vector<char> buffer(len);
        WideCharToMultiByte(CP_UTF8, 0, bstr, -1, buffer.data(), len, NULL, NULL);
        return std::string(buffer.data());
    }
    return "";
}
