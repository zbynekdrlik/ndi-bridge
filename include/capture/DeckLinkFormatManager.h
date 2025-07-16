// DeckLinkFormatManager.h
#pragma once

#include <string>
#include <vector>
#include <atomic>
#include <atlbase.h>
#include "DeckLinkAPI.h"

/**
 * @brief Color space and range information detected from input
 */
struct DetectedColorInfo {
    enum ColorSpace {
        ColorSpace_Unknown,
        ColorSpace_Rec601,  // SD content
        ColorSpace_Rec709   // HD content
    };
    
    enum ColorRange {
        ColorRange_Unknown,
        ColorRange_Limited, // SMPTE levels (16-235)
        ColorRange_Full     // Full range (0-255)
    };
    
    ColorSpace colorSpace = ColorSpace_Unknown;
    ColorRange colorRange = ColorRange_Unknown;
};

/**
 * @brief Manages DeckLink display modes and format changes
 * 
 * Handles display mode enumeration, format detection,
 * and dynamic format changes during capture.
 */
class DeckLinkFormatManager {
public:
    DeckLinkFormatManager();
    ~DeckLinkFormatManager() = default;
    
    /**
     * @brief Find the best display mode for capture
     * @param deckLinkInput DeckLink input interface
     * @param[out] displayMode Selected display mode
     * @param[out] width Frame width
     * @param[out] height Frame height
     * @param[out] frameDuration Frame duration
     * @param[out] frameTimescale Frame timescale
     * @return true if a suitable mode was found
     */
    bool FindBestDisplayMode(IDeckLinkInput* deckLinkInput,
                           BMDDisplayMode& displayMode,
                           long& width, long& height,
                           int64_t& frameDuration, int64_t& frameTimescale);
    
    /**
     * @brief Get list of supported display modes
     * @param deckLinkInput DeckLink input interface
     * @return Vector of display mode names
     */
    std::vector<std::string> GetSupportedFormats(IDeckLinkInput* deckLinkInput) const;
    
    /**
     * @brief Handle format change notification
     * @param events Format change events
     * @param newMode New display mode
     * @param flags Detected format flags
     * @param deckLinkInput DeckLink input interface
     * @param[in,out] displayMode Current display mode
     * @param[in,out] pixelFormat Current pixel format
     * @param[in,out] width Frame width
     * @param[in,out] height Frame height
     * @param[in,out] frameDuration Frame duration
     * @param[in,out] frameTimescale Frame timescale
     * @param[out] colorInfo Detected color space and range
     * @return true if format was changed and capture restarted
     */
    bool HandleFormatChange(BMDVideoInputFormatChangedEvents events,
                          IDeckLinkDisplayMode* newMode,
                          BMDDetectedVideoInputFormatFlags flags,
                          IDeckLinkInput* deckLinkInput,
                          BMDDisplayMode& displayMode,
                          BMDPixelFormat& pixelFormat,
                          long& width, long& height,
                          int64_t& frameDuration, int64_t& frameTimescale,
                          DetectedColorInfo& colorInfo);
    
    /**
     * @brief Enable video input with format detection
     * @param deckLinkInput DeckLink input interface
     * @param displayMode Display mode to use
     * @param pixelFormat Pixel format to use
     * @return true if successful
     */
    bool EnableVideoInput(IDeckLinkInput* deckLinkInput,
                         BMDDisplayMode displayMode,
                         BMDPixelFormat pixelFormat);
    
    /**
     * @brief Get current detected color info
     * @return Current color space and range information
     */
    const DetectedColorInfo& GetColorInfo() const { return m_colorInfo; }
    
    /**
     * @brief Convert BSTR to std::string
     * @param bstr Wide string
     * @return UTF-8 string
     */
    static std::string BSTRToString(BSTR bstr);
    
private:
    // Track if this is the first format detection
    std::atomic<bool> m_firstFormatDetection;
    
    // Current detected color info
    DetectedColorInfo m_colorInfo;
    
    /**
     * @brief Detect color space and range from format flags
     * @param flags Detected format flags from Decklink
     * @return Detected color info
     */
    DetectedColorInfo DetectColorInfo(BMDDetectedVideoInputFormatFlags flags, int height);
};
