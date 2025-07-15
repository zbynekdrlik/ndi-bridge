// DeckLinkDeviceInitializer.h
#pragma once

#include <string>
#include <atlbase.h>
#include "DeckLinkAPI.h"

// Forward declaration
class DeckLinkCaptureDevice;
class DeckLinkCaptureCallback;

/**
 * @brief Handles DeckLink device initialization and discovery
 * 
 * Manages device enumeration, interface setup, serial number
 * retrieval, and callback configuration.
 */
class DeckLinkDeviceInitializer {
public:
    /**
     * @brief Device information structure
     */
    struct DeviceInfo {
        std::string name;
        std::string serialNumber;
    };
    
    DeckLinkDeviceInitializer() = default;
    ~DeckLinkDeviceInitializer() = default;
    
    /**
     * @brief Initialize a DeckLink device by name
     * @param deviceName Name of the device to initialize
     * @param[out] device DeckLink device interface
     * @param[out] deckLinkInput DeckLink input interface
     * @param[out] attributes DeckLink attributes interface
     * @param[out] deviceInfo Device information
     * @param callback Capture callback to register
     * @return true if successful
     */
    bool Initialize(const std::string& deviceName,
                    CComPtr<IDeckLink>& device,
                    CComPtr<IDeckLinkInput>& deckLinkInput,
                    CComPtr<IDeckLinkProfileAttributes>& attributes,
                    DeviceInfo& deviceInfo,
                    DeckLinkCaptureCallback* callback);
    
    /**
     * @brief Initialize from an existing DeckLink device
     * @param device Existing DeckLink device interface
     * @param deviceName Device name
     * @param[out] deckLinkInput DeckLink input interface
     * @param[out] attributes DeckLink attributes interface
     * @param[out] deviceInfo Device information
     * @param callback Capture callback to register
     * @return true if successful
     */
    bool InitializeFromDevice(IDeckLink* device,
                            const std::string& deviceName,
                            CComPtr<IDeckLinkInput>& deckLinkInput,
                            CComPtr<IDeckLinkProfileAttributes>& attributes,
                            DeviceInfo& deviceInfo,
                            DeckLinkCaptureCallback* callback);
    
    /**
     * @brief Get device serial number
     * @param attributes DeckLink attributes interface
     * @return Serial number or empty string if not available
     */
    static std::string GetDeviceSerialNumber(IDeckLinkProfileAttributes* attributes);
    
    /**
     * @brief Create DeckLink iterator
     * @param[out] iterator DeckLink iterator interface
     * @return true if successful
     */
    static bool CreateIterator(CComPtr<IDeckLinkIterator>& iterator);
    
    /**
     * @brief Find device by name
     * @param iterator DeckLink iterator
     * @param deviceName Name to search for
     * @param[out] device Found device
     * @return true if found
     */
    static bool FindDeviceByName(IDeckLinkIterator* iterator,
                               const std::string& deviceName,
                               CComPtr<IDeckLink>& device);
    
private:
    /**
     * @brief Convert BSTR to std::string
     * @param bstr Wide string
     * @return UTF-8 string
     */
    static std::string BSTRToString(BSTR bstr);
};
