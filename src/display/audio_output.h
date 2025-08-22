#pragma once

#include <string>
#include <memory>
#include <cstdint>

namespace ndi_bridge {
namespace display {

class AudioOutput {
public:
    AudioOutput() = default;
    virtual ~AudioOutput() = default;
    
    // Initialize audio system
    virtual bool initialize() = 0;
    
    // Shutdown audio system
    virtual void shutdown() = 0;
    
    // Open audio device for specific display
    // display_id: 0, 1, or 2 corresponding to HDMI outputs
    virtual bool openDevice(int display_id) = 0;
    
    // Close audio device
    virtual void closeDevice() = 0;
    
    // Check if device is open
    virtual bool isOpen() const = 0;
    
    // Write audio samples to device
    // samples: Interleaved audio samples
    // channels: Number of audio channels
    // num_samples: Number of samples per channel
    // sample_rate: Sample rate in Hz
    virtual bool writeAudio(const int16_t* samples, int channels, 
                          int num_samples, int sample_rate) = 0;
    
    // Get current display ID
    virtual int getCurrentDisplayId() const { return current_display_id_; }
    
protected:
    int current_display_id_ = -1;
};

// Factory function to create appropriate audio output
std::unique_ptr<AudioOutput> createAudioOutput();

} // namespace display
} // namespace ndi_bridge