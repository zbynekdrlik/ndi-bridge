// DeckLinkFormatManager.cpp
#include "capture/DeckLinkFormatManager.h"
#include <iostream>
#include <windows.h>

DeckLinkFormatManager::DeckLinkFormatManager()
    : m_firstFormatDetection(true) {
}

bool DeckLinkFormatManager::FindBestDisplayMode(IDeckLinkInput* deckLinkInput,
                                               BMDDisplayMode& displayMode,
                                               long& width, long& height,
                                               int64_t& frameDuration, int64_t& frameTimescale) {
    CComPtr<IDeckLinkDisplayModeIterator> displayModeIterator;
    HRESULT result = deckLinkInput->GetDisplayModeIterator(&displayModeIterator);
    if (result != S_OK) {
        return false;
    }
    
    CComPtr<IDeckLinkDisplayMode> mode;
    BMDDisplayMode selectedMode = bmdModeUnknown;
    
    // Try to find 1080p60 mode first (from reference)
    while (displayModeIterator->Next(&mode) == S_OK) {
        BMDDisplayMode currentMode = mode->GetDisplayMode();
        if (currentMode == bmdModeHD1080p6000 || currentMode == bmdModeHD1080p5994) {
            selectedMode = currentMode;
            width = mode->GetWidth();
            height = mode->GetHeight();
            mode->GetFrameRate(&frameDuration, &frameTimescale);
            std::cout << "[DeckLink] Found Full HD 60fps mode" << std::endl;
            break;
        }
        if (selectedMode == bmdModeUnknown) {
            selectedMode = currentMode;
            width = mode->GetWidth();
            height = mode->GetHeight();
            mode->GetFrameRate(&frameDuration, &frameTimescale);
        }
        mode.Release();
    }
    
    if (selectedMode == bmdModeUnknown) {
        return false;
    }
    
    displayMode = selectedMode;
    return true;
}

std::vector<std::string> DeckLinkFormatManager::GetSupportedFormats(IDeckLinkInput* deckLinkInput) const {
    std::vector<std::string> formats;
    
    if (!deckLinkInput) {
        return formats;
    }
    
    CComPtr<IDeckLinkDisplayModeIterator> displayModeIterator;
    HRESULT result = deckLinkInput->GetDisplayModeIterator(&displayModeIterator);
    if (result != S_OK) {
        return formats;
    }
    
    CComPtr<IDeckLinkDisplayMode> displayMode;
    while (displayModeIterator->Next(&displayMode) == S_OK) {
        BSTR modeName;
        if (displayMode->GetName(&modeName) == S_OK) {
            formats.push_back(BSTRToString(modeName));
            SysFreeString(modeName);
        }
        displayMode.Release();
    }
    
    return formats;
}

bool DeckLinkFormatManager::HandleFormatChange(BMDVideoInputFormatChangedEvents events,
                                              IDeckLinkDisplayMode* newMode,
                                              BMDDetectedVideoInputFormatFlags flags,
                                              IDeckLinkInput* deckLinkInput,
                                              BMDDisplayMode& displayMode,
                                              BMDPixelFormat& pixelFormat,
                                              long& width, long& height,
                                              int64_t& frameDuration, int64_t& frameTimescale) {
    try {
        if (!newMode) {
            return false;
        }
        
        // Get new format details
        BMDDisplayMode newDisplayMode = newMode->GetDisplayMode();
        int newWidth = newMode->GetWidth();
        int newHeight = newMode->GetHeight();
        
        // Determine new pixel format
        BMDPixelFormat newPixelFormat = pixelFormat;
        if (flags & bmdDetectedVideoInputRGB444) {
            newPixelFormat = bmdFormat8BitBGRA;
        } else if (flags & bmdDetectedVideoInputYCbCr422) {
            newPixelFormat = bmdFormat8BitYUV;
        }
        
        // Check if format actually changed
        bool formatChanged = (displayMode != newDisplayMode) || 
                           (pixelFormat != newPixelFormat);
        
        if (formatChanged) {
            BSTR modeName;
            if (newMode->GetName(&modeName) == S_OK) {
                std::cout << "[DeckLink] Format changed to: " << BSTRToString(modeName) << std::endl;
                SysFreeString(modeName);
            }
            
            // Update format info
            width = newWidth;
            height = newHeight;
            displayMode = newDisplayMode;
            pixelFormat = newPixelFormat;
            
            // Get frame rate
            newMode->GetFrameRate(&frameDuration, &frameTimescale);
            double fps = static_cast<double>(frameTimescale) / static_cast<double>(frameDuration);
            std::cout << "[DeckLink] New format: " << width << "x" << height 
                     << " @ " << fps << " fps" << std::endl;
            
            // Handle format change (adapted from reference)
            bool expected = true;
            if (m_firstFormatDetection.compare_exchange_strong(expected, false) && formatChanged) {
                std::cout << "[DeckLink] Applying detected format..." << std::endl;
                
                // Restart capture with detected format
                deckLinkInput->StopStreams();
                Sleep(50);
                
                // Re-enable with detected format
                HRESULT result = deckLinkInput->EnableVideoInput(
                    displayMode, 
                    pixelFormat,
                    bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection
                );
                
                if (result == S_OK) {
                    result = deckLinkInput->StartStreams();
                    if (result == S_OK) {
                        std::cout << "[DeckLink] Capture restarted with detected format" << std::endl;
                        return true;
                    }
                }
            }
        }
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in HandleFormatChange: " << e.what() << std::endl;
    }
    
    return false;
}

bool DeckLinkFormatManager::EnableVideoInput(IDeckLinkInput* deckLinkInput,
                                           BMDDisplayMode displayMode,
                                           BMDPixelFormat pixelFormat) {
    // Enable video input with format detection (from reference)
    HRESULT result = deckLinkInput->EnableVideoInput(
        displayMode, 
        pixelFormat,
        bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection
    );
    
    if (result != S_OK) {
        std::cerr << "[DeckLink] Failed to enable video input" << std::endl;
        return false;
    }
    
    return true;
}

std::string DeckLinkFormatManager::BSTRToString(BSTR bstr) {
    if (!bstr) return "";
    
    int len = WideCharToMultiByte(CP_UTF8, 0, bstr, -1, NULL, 0, NULL, NULL);
    if (len > 0) {
        std::vector<char> buffer(len);
        WideCharToMultiByte(CP_UTF8, 0, bstr, -1, buffer.data(), len, NULL, NULL);
        return std::string(buffer.data());
    }
    return "";
}
