#pragma once

#include "audio_output.h"
#include <alsa/asoundlib.h>
#include <string>
#include <vector>

namespace ndi_bridge {
namespace display {

class ALSAAudioOutput : public AudioOutput {
public:
    ALSAAudioOutput();
    ~ALSAAudioOutput() override;
    
    bool initialize() override;
    void shutdown() override;
    bool openDevice(int display_id) override;
    void closeDevice() override;
    bool isOpen() const override;
    bool writeAudio(const int16_t* samples, int channels, 
                   int num_samples, int sample_rate) override;
    
private:
    // Get ALSA device name for display ID
    std::string getDeviceForDisplay(int display_id) const;
    
    // Configure ALSA hardware parameters
    bool configureHardwareParams(int channels, int sample_rate);
    
    snd_pcm_t* pcm_handle_ = nullptr;
    
    // Current audio configuration
    int current_channels_ = 0;
    int current_sample_rate_ = 0;
    
    // Buffer for handling partial frames
    std::vector<int16_t> buffer_;
};

} // namespace display
} // namespace ndi_bridge