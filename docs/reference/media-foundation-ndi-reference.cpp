// Original single-file Media Bridge implementation
// This file is preserved for reference to show the original interactive menu functionality
// and other features that may have been modified during refactoring.

// Ensure NOMINMAX is defined so that std::min works correctly.
#ifndef NOMINMAX
#define NOMINMAX
#endif

// Define missing error codes if not already defined.
#ifndef MF_E_HW_MFT_FAILED_START_STREAMING
#define MF_E_HW_MFT_FAILED_START_STREAMING ((HRESULT)0xC00D3EA2L)
#endif

#ifndef MF_E_DEVICE_INVALIDATED
#define MF_E_DEVICE_INVALIDATED ((HRESULT)0xC00D36B4L)
#endif

#ifndef MF_E_NO_MORE_TYPES
#define MF_E_NO_MORE_TYPES ((HRESULT)0xC00D36B9L)
#endif

#ifndef MF_E_VIDEO_RECORDING_DEVICE_LOCKED
#define MF_E_VIDEO_RECORDING_DEVICE_LOCKED ((HRESULT)0xC00D3E85L)
#endif

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <comdef.h>
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <conio.h>       // for _kbhit(), _getch()
#include <thread>        // for std::this_thread::sleep_for
#include <chrono>        // for std::chrono::milliseconds
#include <algorithm>     // for std::min
#include <cstdlib>

#include <Processing.NDI.Lib.h>

// Uncomment if auto-linking is enabled:
// #pragma comment(lib, "mfplat.lib")
// #pragma comment(lib, "mfreadwrite.lib")
// #pragma comment(lib, "mfuuid.lib")
// #pragma comment(lib, "Mf.lib")
// #pragma comment(lib, "Processing.NDI.Lib.lib")

// Global capture parameters.
static int    g_width = 0;
static int    g_height = 0;
static UINT32 g_fpsN = 0;
static UINT32 g_fpsD = 0;
static UINT32 g_interlaceMode = 0;  // 2 = progressive, 3 = interlaced
static GUID   g_subtype = { 0 };
static std::vector<BYTE> g_frameBuffer;
static bool   g_quit = false;

// Save the chosen device's friendly name (for re‑enumeration).
static std::wstring g_chosenDeviceName;

//---------------------------------------------------------------------
// Helper: Print HRESULT errors using _com_error.
inline bool FAILED_MSG(const char* msg, HRESULT hr)
{
    if (FAILED(hr))
    {
        _com_error err(hr);
        std::cerr << msg << " (hr=0x" << std::hex << hr << "): "
            << err.ErrorMessage() << "\n";
        return true;
    }
    return false;
}

//---------------------------------------------------------------------
// YUY2 -> UYVY conversion.
void YUY2toUYVY(const uint8_t* src, uint8_t* dst, int width, int height)
{
    int totalPixels = width * height;
    for (int i = 0; i < totalPixels; i += 2)
    {
        dst[0] = src[1];
        dst[1] = src[0];
        dst[2] = src[3];
        dst[3] = src[2];
        src += 4;
        dst += 4;
    }
}

//---------------------------------------------------------------------
// NV12 -> UYVY conversion.
void NV12toUYVY(const uint8_t* nv12, uint8_t* uyvy, int width, int height)
{
    const uint8_t* Yplane = nv12;
    const uint8_t* UVplane = nv12 + width * height;
    for (int y = 0; y < height; y++)
    {
        int uvRow = y / 2;
        for (int x = 0; x < width; x += 2)
        {
            uint8_t Y0 = Yplane[y * width + x];
            uint8_t Y1 = Yplane[y * width + (x + 1)];
            int uvCol = x / 2;
            uint8_t U = UVplane[uvRow * (width / 2) * 2 + uvCol * 2 + 0];
            uint8_t V = UVplane[uvRow * (width / 2) * 2 + uvCol * 2 + 1];
            int outIndex = (y * width + x) * 2;
            uyvy[outIndex + 0] = U;
            uyvy[outIndex + 1] = Y0;
            uyvy[outIndex + 2] = V;
            uyvy[outIndex + 3] = Y1;
        }
    }
}

//---------------------------------------------------------------------
// Enumerate all Media Foundation capture devices.
HRESULT EnumerateDevices(std::vector<IMFActivate*>& devices, std::vector<std::wstring>& names)
{
    devices.clear();
    names.clear();

    IMFAttributes* pAttrs = nullptr;
    HRESULT hr = MFCreateAttributes(&pAttrs, 1);
    if (FAILED_MSG("MFCreateAttributes() failed", hr))
        return hr;

    hr = pAttrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    if (FAILED_MSG("SetGUID(...) failed", hr))
    {
        pAttrs->Release();
        return hr;
    }

    IMFActivate** ppDevices = nullptr;
    UINT32 count = 0;
    hr = MFEnumDeviceSources(pAttrs, &ppDevices, &count);
    pAttrs->Release();
    if (FAILED_MSG("MFEnumDeviceSources() failed", hr))
        return hr;

    std::cout << "Found " << count << " device(s).\n";
    for (UINT32 i = 0; i < count; i++)
    {
        IMFMediaSource* pSource = nullptr;
        hr = ppDevices[i]->ActivateObject(IID_IMFMediaSource, (void**)&pSource);
        if (SUCCEEDED(hr))
        {
            pSource->Release();
            devices.push_back(ppDevices[i]);
            WCHAR* wName = nullptr;
            UINT32 wLen = 0;
            hr = ppDevices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &wName, &wLen);
            if (SUCCEEDED(hr) && wName)
            {
                names.push_back(wName);
                std::wcout << L"Device " << i << L": " << wName << std::endl;
                CoTaskMemFree(wName);
            }
            else
            {
                names.push_back(L"Unknown Device");
            }
        }
        else
        {
            _com_error err(hr);
            std::cerr << "Device " << i << " does not support IMFMediaSource: "
                << err.ErrorMessage() << "\n";
            ppDevices[i]->Release();
        }
    }
    CoTaskMemFree(ppDevices);
    return S_OK;
}

//---------------------------------------------------------------------
// Re-enumerate devices and return the IMFActivate pointer matching the given friendly name.
HRESULT ReinitActivateFromName(const std::wstring& targetName, IMFActivate** ppActivate)
{
    *ppActivate = nullptr;
    std::vector<IMFActivate*> devices;
    std::vector<std::wstring> names;
    HRESULT hr = EnumerateDevices(devices, names);
    if (FAILED(hr))
        return hr;
    for (size_t i = 0; i < devices.size(); i++)
    {
        if (names[i] == targetName)
        {
            *ppActivate = devices[i];
            (*ppActivate)->AddRef();
        }
        else
        {
            devices[i]->Release();
        }
    }
    if (!*ppActivate)
    {
        std::wcerr << L"Re-enumeration: Device \"" << targetName << L"\" not found.\n";
        return E_FAIL;
    }
    std::wcout << L"Re-enumeration succeeded. Using device: " << targetName << std::endl;
    return S_OK;
}

//---------------------------------------------------------------------
// Create a SourceReader from the given IMFActivate.
HRESULT CreateSourceReader(IMFActivate* pActivate, IMFSourceReader** ppReader)
{
    if (!pActivate || !ppReader)
        return E_POINTER;
    IMFMediaSource* pSource = nullptr;
    HRESULT hr = pActivate->ActivateObject(IID_PPV_ARGS(&pSource));
    if (FAILED_MSG("ActivateObject(device) failed", hr))
        return hr;
    IMFSourceReader* pReader = nullptr;
    hr = MFCreateSourceReaderFromMediaSource(pSource, nullptr, &pReader);
    pSource->Release();
    if (FAILED_MSG("MFCreateSourceReaderFromMediaSource() failed", hr))
        return hr;
    pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
    pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
    std::cout << "SourceReader created successfully.\n";
    *ppReader = pReader;
    return S_OK;
}

//---------------------------------------------------------------------
// Attempt to set the output to UYVY.
HRESULT TrySetOutputToUYVY(IMFSourceReader* pReader)
{
    IMFMediaType* pType = nullptr;
    HRESULT hr = MFCreateMediaType(&pType);
    if (FAILED(hr) || !pType)
    {
        std::cerr << "MFCreateMediaType(UYVY) failed.\n";
        return hr;
    }
    pType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    pType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_UYVY);
    hr = pReader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, pType);
    pType->Release();
    if (FAILED(hr))
    {
        std::cerr << "Could not set UYVY output. Using device default.\n";
    }
    return hr;
}

//---------------------------------------------------------------------
// Retrieve the final negotiated media type: width, height, fps, interlace mode, and subtype.
HRESULT GetFinalFormat(IMFSourceReader* pReader, GUID& sub)
{
    IMFMediaType* pOut = nullptr;
    HRESULT hr = pReader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &pOut);
    if (FAILED_MSG("GetCurrentMediaType() failed", hr))
        return hr;
    UINT32 w = 0, h = 0;
    MFGetAttributeSize(pOut, MF_MT_FRAME_SIZE, &w, &h);
    g_width = (int)w;
    g_height = (int)h;
    UINT32 fpsN = 0, fpsD = 0;
    MFGetAttributeRatio(pOut, MF_MT_FRAME_RATE, &fpsN, &fpsD);
    if (fpsD == 0)
        fpsD = 1;
    g_fpsN = fpsN;
    g_fpsD = fpsD;
    pOut->GetUINT32(MF_MT_INTERLACE_MODE, &g_interlaceMode);
    pOut->GetGUID(MF_MT_SUBTYPE, &sub);
    g_subtype = sub;
    pOut->Release();
    std::cout << "Final format: " << g_width << "x" << g_height << " @ "
        << g_fpsN << "/" << g_fpsD << " fps.\n";
    return S_OK;
}

//---------------------------------------------------------------------
// The main capture loop: read samples, convert if needed, and send frames to NDI.
HRESULT CaptureLoop(IMFSourceReader* pReader, const std::string& ndiName)
{
    if (!NDIlib_initialize())
    {
        std::cerr << "NDI runtime not found.\n";
        return E_FAIL;
    }
    NDIlib_send_create_t desc;
    ZeroMemory(&desc, sizeof(desc));
    desc.p_ndi_name = ndiName.c_str();
    NDIlib_send_instance_t pNDISender = NDIlib_send_create(&desc);
    if (!pNDISender)
    {
        std::cerr << "Failed to create NDI sender.\n";
        return E_FAIL;
    }
    double fps = (g_fpsD != 0) ? (double)g_fpsN / (double)g_fpsD : 0.0;
    std::cout << "Starting capture with final format: " << g_width << "x" << g_height
        << " @ " << fps << " fps.\n";
    std::cout << "NDI stream: \"" << ndiName << "\"\n";
    std::cout << "Press ENTER to stop.\n";
    DWORD outBytes = (DWORD)(g_width * g_height * 2);
    g_frameBuffer.resize(outBytes);

    while (!g_quit)
    {
        if (_kbhit())
        {
            int c = _getch();
            if (c == 13)
            {
                std::cout << "User requested exit.\n";
                g_quit = true;
                break;
            }
        }
        DWORD streamIndex = 0, flags = 0;
        LONGLONG llTime = 0;
        IMFSample* pSample = nullptr;
        HRESULT hr = pReader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &streamIndex, &flags, &llTime, &pSample);
        if (FAILED(hr))
        {
            if (hr == MF_E_HW_MFT_FAILED_START_STREAMING)
            {
                _com_error err(hr);
                std::cerr << "ReadSample returned MF_E_HW_MFT_FAILED_START_STREAMING: "
                    << err.ErrorMessage() << ". Waiting and returning error for reinit...\n";
                if (pSample)
                    pSample->Release();
                std::this_thread::sleep_for(std::chrono::milliseconds(1000));
                NDIlib_send_destroy(pNDISender);
                NDIlib_destroy();
                return hr;
            }
            if (hr == MF_E_DEVICE_INVALIDATED)
            {
                std::cerr << "Device invalidated (unplugged?)\n";
                if (pSample)
                    pSample->Release();
                NDIlib_send_destroy(pNDISender);
                NDIlib_destroy();
                return hr;
            }
            _com_error err(hr);
            std::cerr << "ReadSample failed (hr=0x" << std::hex << hr << "): "
                << err.ErrorMessage() << "\n";
            if (pSample)
                pSample->Release();
            break;
        }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM)
        {
            std::cerr << "End of stream encountered.\n";
            if (pSample)
                pSample->Release();
            break;
        }
        if (!pSample)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            continue;
        }
        IMFMediaBuffer* pBuffer = nullptr;
        hr = pSample->ConvertToContiguousBuffer(&pBuffer);
        pSample->Release();
        if (FAILED(hr) || !pBuffer)
        {
            if (pBuffer)
                pBuffer->Release();
            continue;
        }
        BYTE* pData = nullptr;
        DWORD cbMax = 0, cbCurrent = 0;
        hr = pBuffer->Lock(&pData, &cbMax, &cbCurrent);
        if (SUCCEEDED(hr) && pData)
        {
            if (g_subtype == MFVideoFormat_UYVY)
            {
                if (cbCurrent >= outBytes)
                    memcpy(g_frameBuffer.data(), pData, outBytes);
            }
            else if (g_subtype == MFVideoFormat_YUY2)
            {
                if (cbCurrent >= outBytes)
                    YUY2toUYVY(pData, g_frameBuffer.data(), g_width, g_height);
            }
            else if (g_subtype.Data1 == 0x3231564E) // NV12
            {
                DWORD needed = (DWORD)(g_width * g_height * 3 / 2);
                if (cbCurrent >= needed)
                    NV12toUYVY(pData, g_frameBuffer.data(), g_width, g_height);
            }
            NDIlib_video_frame_v2_t frame;
            ZeroMemory(&frame, sizeof(frame));
            frame.xres = g_width;
            frame.yres = g_height;
            frame.FourCC = NDIlib_FourCC_type_UYVY;
            frame.line_stride_in_bytes = g_width * 2;
            frame.p_data = g_frameBuffer.data();
            frame.frame_rate_N = g_fpsN;
            frame.frame_rate_D = g_fpsD;
            frame.picture_aspect_ratio = (float)g_width / (float)g_height;
            frame.timecode = NDIlib_send_timecode_synthesize;
            frame.frame_format_type = (g_interlaceMode == 2)
                ? NDIlib_frame_format_type_progressive
                : NDIlib_frame_format_type_interleaved;
            NDIlib_send_send_video_v2(pNDISender, &frame);
        }
        if (pBuffer)
        {
            pBuffer->Unlock();
            pBuffer->Release();
        }
    }
    NDIlib_send_destroy(pNDISender);
    NDIlib_destroy();
    return S_OK;
}

//---------------------------------------------------------------------
// RunCaptureWithReinit: repeatedly attempt to initialize and run the capture pipeline.
// If errors occur indicating the device is unavailable, reinitialize MF and re-enumerate devices.
HRESULT RunCaptureWithReinit(IMFActivate* pActivate, const std::wstring& chosenName, const std::string& ndiName)
{
    int retryDelay = 1000; // Start at 1 second.
    const int maxDelay = 5000; // Maximum delay 5 seconds.
    int attempt = 0;
    while (!g_quit)
    {
        attempt++;
        std::cout << "Reinit attempt #" << attempt << std::endl;
        IMFSourceReader* pReader = nullptr;
        HRESULT hr = CreateSourceReader(pActivate, &pReader);
        if (FAILED(hr))
        {
            if (hr == E_NOINTERFACE || hr == MF_E_DEVICE_INVALIDATED ||
                hr == MF_E_HW_MFT_FAILED_START_STREAMING || hr == MF_E_VIDEO_RECORDING_DEVICE_LOCKED)
            {
                _com_error err(hr);
                std::cerr << "CreateSourceReader failed (" << err.ErrorMessage()
                    << "). Reinitializing MF and re-enumerating...\n";
                if (hr == MF_E_VIDEO_RECORDING_DEVICE_LOCKED)
                {
                    MFShutdown();
                    hr = MFStartup(MF_VERSION);
                    if (FAILED(hr))
                    {
                        std::cerr << "MFStartup failed during reinit.\n";
                        return hr;
                    }
                }
                IMFActivate* pNewActivate = nullptr;
                hr = ReinitActivateFromName(chosenName, &pNewActivate);
                if (SUCCEEDED(hr) && pNewActivate)
                {
                    pActivate->Release();
                    pActivate = pNewActivate;
                }
                else
                {
                    std::cerr << "Re-enumeration failed. Waiting...\n";
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(retryDelay));
                retryDelay = std::min(retryDelay + 1000, maxDelay);
                continue;
            }
            else
            {
                _com_error err(hr);
                std::cerr << "CreateSourceReader failed (hr=0x" << std::hex << hr
                    << "): " << err.ErrorMessage() << "\n";
                std::this_thread::sleep_for(std::chrono::milliseconds(retryDelay));
                continue;
            }
        }
        pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
        pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
        TrySetOutputToUYVY(pReader);
        hr = GetFinalFormat(pReader, g_subtype);
        if (FAILED(hr))
        {
            pReader->Release();
            if (hr == MF_E_DEVICE_INVALIDATED || hr == E_NOINTERFACE || hr == MF_E_HW_MFT_FAILED_START_STREAMING)
            {
                std::cerr << "Device error during GetFinalFormat. Waiting...\n";
                std::this_thread::sleep_for(std::chrono::milliseconds(retryDelay));
                retryDelay = std::min(retryDelay + 1000, maxDelay);
                continue;
            }
            else
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(retryDelay));
                continue;
            }
        }
        HRESULT runHR = CaptureLoop(pReader, ndiName);
        pReader->Release();
        if ((runHR == MF_E_DEVICE_INVALIDATED || runHR == MF_E_HW_MFT_FAILED_START_STREAMING ||
            runHR == MF_E_VIDEO_RECORDING_DEVICE_LOCKED) && !g_quit)
        {
            _com_error err(runHR);
            std::cerr << "CaptureLoop error (hr=0x" << std::hex << runHR
                << "): " << err.ErrorMessage() << ". Reinitializing...\n";
            std::this_thread::sleep_for(std::chrono::milliseconds(retryDelay));
            retryDelay = std::min(retryDelay + 1000, maxDelay);
            continue;
        }
        else
        {
            std::cout << "Capture loop ended normally.\n";
            break;
        }
    }
    return S_OK;
}

//---------------------------------------------------------------------
// main: If command-line parameters are provided, treat the first parameter as the device name and the second as the NDI stream name.
// Otherwise, show the interactive menu.
int main(int argc, char* argv[])
{
    HRESULT hr = MFStartup(MF_VERSION);
    if (FAILED_MSG("MFStartup failed", hr))
        return -1;

    bool useCmdLine = false;
    std::wstring cmdDeviceName;
    std::string ndiName;

    if (argc >= 3)
    {
        try {
            std::string devNameStr = argv[1];
            cmdDeviceName = std::wstring(devNameStr.begin(), devNameStr.end());
            ndiName = argv[2];
            std::wcout << L"Command-line mode: device name = \"" << cmdDeviceName
                << L"\", NDI stream name = " << std::wstring(ndiName.begin(), ndiName.end()) << L"\n";
            useCmdLine = true;
        }
        catch (...)
        {
            std::cerr << "Error parsing command-line parameters. Falling back to interactive mode.\n";
            useCmdLine = false;
        }
    }

    std::vector<IMFActivate*> devList;
    std::vector<std::wstring> devNames;
    hr = EnumerateDevices(devList, devNames);
    if (FAILED_MSG("EnumerateDevices() failed", hr) || devList.empty())
    {
        std::cerr << "No capture devices found.\n";
        MFShutdown();
        return -1;
    }

    int chosenIndex = -1;
    if (useCmdLine)
    {
        bool found = false;
        for (size_t i = 0; i < devNames.size(); i++)
        {
            if (devNames[i] == cmdDeviceName)
            {
                chosenIndex = static_cast<int>(i);
                found = true;
                break;
            }
        }
        if (!found)
        {
            std::cerr << "Device with name \"" << std::string(cmdDeviceName.begin(), cmdDeviceName.end())
                << "\" not found. Falling back to interactive mode.\n";
            useCmdLine = false;
        }
    }

    if (!useCmdLine)
    {
        std::wcout << L"Available Media Foundation Devices:\n";
        for (size_t i = 0; i < devList.size(); i++)
        {
            std::wcout << i << L": " << devNames[i] << std::endl;
        }
        std::cout << "Select device index: ";
        std::cin >> chosenIndex;
        std::cout << "Enter NDI stream name: ";
        std::cin >> ndiName;
    }

    if (chosenIndex < 0 || chosenIndex >= (int)devList.size())
    {
        std::cerr << "Invalid device index.\n";
        for (auto d : devList)
            d->Release();
        MFShutdown();
        return -1;
    }

    std::wcout << L"Using device: " << devNames[chosenIndex] << std::endl;
    g_chosenDeviceName = devNames[chosenIndex];

    IMFActivate* pActivate = devList[chosenIndex];
    pActivate->AddRef();
    for (size_t i = 0; i < devList.size(); i++)
    {
        if ((int)i != chosenIndex)
            devList[i]->Release();
    }
    devList.clear();

    std::cout << "Starting capture pipeline...\n";
    hr = RunCaptureWithReinit(pActivate, g_chosenDeviceName, ndiName);
    pActivate->Release();
    MFShutdown();
    std::cout << "Exiting.\n";
    // In command-line mode, wait for user input before closing.
    if (useCmdLine)
    {
        std::cout << "Press ENTER to exit.\n";
        std::cin.ignore();
        std::cin.get();
    }
    return (SUCCEEDED(hr) ? 0 : -1);
}
