// DeckLinkCaptureCallback.h
#pragma once

#include <atomic>
#include "DeckLinkAPI.h"

// Forward declaration
class DeckLinkCaptureDevice;

/**
 * @brief Callback handler for DeckLink input events
 * 
 * Implements IDeckLinkInputCallback to receive frame arrival
 * and format change notifications from the DeckLink hardware.
 */
class DeckLinkCaptureCallback : public IDeckLinkInputCallback {
private:
    std::atomic<ULONG> m_refCount;
    DeckLinkCaptureDevice* m_owner;
    
public:
    /**
     * @brief Construct a new callback handler
     * @param owner The parent DeckLinkCaptureDevice instance
     */
    explicit DeckLinkCaptureCallback(DeckLinkCaptureDevice* owner);
    
    // IUnknown methods
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv) override;
    virtual ULONG STDMETHODCALLTYPE AddRef(void) override;
    virtual ULONG STDMETHODCALLTYPE Release(void) override;
    
    // IDeckLinkInputCallback methods
    virtual HRESULT STDMETHODCALLTYPE VideoInputFormatChanged(
        BMDVideoInputFormatChangedEvents notificationEvents,
        IDeckLinkDisplayMode* newMode,
        BMDDetectedVideoInputFormatFlags detectedSignalFlags) override;
    
    virtual HRESULT STDMETHODCALLTYPE VideoInputFrameArrived(
        IDeckLinkVideoInputFrame* videoFrame,
        IDeckLinkAudioInputPacket* audioPacket) override;
};
