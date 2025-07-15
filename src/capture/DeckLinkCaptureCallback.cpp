// DeckLinkCaptureCallback.cpp
#include "capture/DeckLinkCaptureCallback.h"
#include "capture/DeckLinkCaptureDevice.h"

DeckLinkCaptureCallback::DeckLinkCaptureCallback(DeckLinkCaptureDevice* owner) 
    : m_refCount(1)
    , m_owner(owner) {
}

HRESULT STDMETHODCALLTYPE DeckLinkCaptureCallback::QueryInterface(REFIID iid, LPVOID *ppv) {
    if (iid == IID_IUnknown) {
        *ppv = this;
        AddRef();
        return S_OK;
    }
    if (iid == IID_IDeckLinkInputCallback) {
        *ppv = (IDeckLinkInputCallback*)this;
        AddRef();
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE DeckLinkCaptureCallback::AddRef(void) {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE DeckLinkCaptureCallback::Release(void) {
    ULONG refCount = --m_refCount;
    if (refCount == 0) {
        delete this;
    }
    return refCount;
}

HRESULT STDMETHODCALLTYPE DeckLinkCaptureCallback::VideoInputFormatChanged(
    BMDVideoInputFormatChangedEvents notificationEvents,
    IDeckLinkDisplayMode* newMode,
    BMDDetectedVideoInputFormatFlags detectedSignalFlags) {
    
    if (m_owner) {
        m_owner->OnFormatChanged(notificationEvents, newMode, detectedSignalFlags);
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE DeckLinkCaptureCallback::VideoInputFrameArrived(
    IDeckLinkVideoInputFrame* videoFrame,
    IDeckLinkAudioInputPacket* audioPacket) {
    
    if (m_owner && videoFrame) {
        m_owner->OnFrameArrived(videoFrame);
    }
    return S_OK;
}
