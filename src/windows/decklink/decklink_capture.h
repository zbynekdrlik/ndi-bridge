// decklink_capture.h - Wrapper for DeckLinkCaptureDevice to match main.cpp expectations
#pragma once

#include "../../capture/DeckLinkCaptureDevice.h"

namespace ndi_bridge {

// Wrapper class to adapt DeckLinkCaptureDevice to the expected interface
class DeckLinkCapture : public DeckLinkCaptureDevice {
public:
    DeckLinkCapture() = default;
    ~DeckLinkCapture() = default;
};

} // namespace ndi_bridge
