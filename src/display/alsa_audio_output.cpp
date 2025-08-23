#include "alsa_audio_output.h"
#include "../common/logger.h"
#include <cstring>
#include <unistd.h>

namespace ndi_bridge {
namespace display {

ALSAAudioOutput::ALSAAudioOutput() {
    // hw_params will be allocated on stack when needed in configureHardwareParams
}

ALSAAudioOutput::~ALSAAudioOutput() {
    shutdown();
}

bool ALSAAudioOutput::initialize() {
    // ALSA is initialized per-device, nothing to do here
    return true;
}

void ALSAAudioOutput::shutdown() {
    closeDevice();
}

std::string ALSAAudioOutput::getDeviceForDisplay(int display_id) const {
    // Map display ID to ALSA HDMI PCM device
    // Try to auto-detect the correct card (1 or 2) for HDMI audio
    // Different systems have HDMI audio on different cards
    
    std::string device;
    snd_pcm_t* test_handle = nullptr;
    
    // First try card 1 (common on consumer boards with Intel HDA)
    // HDMI port numbering can vary by chipset
    switch (display_id) {
        case 0: device = "hw:1,3"; break;  // HDMI-1 often uses device 3
        case 1: device = "hw:1,7"; break;  // HDMI-2 often uses device 7  
        case 2: device = "hw:1,8"; break;  // HDMI-3 often uses device 8
        default: device = "hw:1,3"; break;
    }
    
    // Test if the device exists and can be opened
    if (snd_pcm_open(&test_handle, device.c_str(), SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK) == 0) {
        snd_pcm_close(test_handle);
        Logger::info("Using audio device " + device + " for display " + std::to_string(display_id));
        return device;
    }
    
    // If card 1 didn't work, try card 2 (industrial/server boards)
    switch (display_id) {
        case 0: device = "hw:2,7"; break;  // HDMI-1
        case 1: device = "hw:2,3"; break;  // HDMI-2 (confirmed on test box)
        case 2: device = "hw:2,8"; break;  // HDMI-3
        default: device = "hw:2,7"; break;
    }
    
    // Test card 2
    if (snd_pcm_open(&test_handle, device.c_str(), SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK) == 0) {
        snd_pcm_close(test_handle);
        Logger::info("Using audio device " + device + " for display " + std::to_string(display_id));
        return device;
    }
    
    // If neither worked, log error and return card 1 as fallback
    Logger::error("Could not detect HDMI audio device for display " + std::to_string(display_id) + ", using fallback");
    switch (display_id) {
        case 0: return "hw:1,3";
        case 1: return "hw:1,7";
        case 2: return "hw:1,8";
        default: return "hw:1,3";
    }
}

bool ALSAAudioOutput::openDevice(int display_id) {
    if (pcm_handle_) {
        closeDevice();
    }
    
    std::string device = getDeviceForDisplay(display_id);
    if (device.empty()) {
        return false;
    }
    
    current_display_id_ = display_id;
    
    // Open PCM device for playback
    int err = snd_pcm_open(&pcm_handle_, device.c_str(), 
                           SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        Logger::error("Failed to open audio device " + device + ": " + 
                     snd_strerror(err));
        pcm_handle_ = nullptr;
        return false;
    }
    
    Logger::info("Opened audio device " + device + " for display " + 
                std::to_string(display_id));
    
    // Device will be configured on first audio write
    current_channels_ = 0;
    current_sample_rate_ = 0;
    
    return true;
}

void ALSAAudioOutput::closeDevice() {
    if (pcm_handle_) {
        snd_pcm_drop(pcm_handle_);
        snd_pcm_close(pcm_handle_);
        pcm_handle_ = nullptr;
        
        Logger::info("Closed audio device for display " + 
                    std::to_string(current_display_id_));
    }
    
    current_display_id_ = -1;
    current_channels_ = 0;
    current_sample_rate_ = 0;
    buffer_.clear();
}

bool ALSAAudioOutput::isOpen() const {
    return pcm_handle_ != nullptr;
}

bool ALSAAudioOutput::configureHardwareParams(int channels, int sample_rate) {
    if (!pcm_handle_) {
        return false;
    }
    
    int err;
    
    // Allocate hardware parameters on stack
    snd_pcm_hw_params_t* hw_params;
    snd_pcm_hw_params_alloca(&hw_params);
    
    // Initialize hardware parameters
    err = snd_pcm_hw_params_any(pcm_handle_, hw_params);
    if (err < 0) {
        Logger::error("Failed to initialize hw params: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set access type to interleaved
    err = snd_pcm_hw_params_set_access(pcm_handle_, hw_params,
                                       SND_PCM_ACCESS_RW_INTERLEAVED);
    if (err < 0) {
        Logger::error("Failed to set access type: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set sample format to signed 16-bit little-endian
    err = snd_pcm_hw_params_set_format(pcm_handle_, hw_params,
                                       SND_PCM_FORMAT_S16_LE);
    if (err < 0) {
        Logger::error("Failed to set format: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set number of channels
    err = snd_pcm_hw_params_set_channels(pcm_handle_, hw_params, channels);
    if (err < 0) {
        Logger::error("Failed to set channels to " + std::to_string(channels) + 
                     ": " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set sample rate
    unsigned int actual_rate = sample_rate;
    err = snd_pcm_hw_params_set_rate_near(pcm_handle_, hw_params, 
                                          &actual_rate, 0);
    if (err < 0) {
        Logger::error("Failed to set sample rate: " + std::string(snd_strerror(err)));
        return false;
    }
    
    if (actual_rate != (unsigned int)sample_rate) {
        Logger::warning("Sample rate adjusted from " + std::to_string(sample_rate) +
                       " to " + std::to_string(actual_rate));
    }
    
    // Set period size to match typical NDI frame size (1024 frames)
    // This prevents buffer underruns when NDI delivers 1024 samples
    snd_pcm_uframes_t period_size = 1024;
    err = snd_pcm_hw_params_set_period_size_near(pcm_handle_, hw_params,
                                                 &period_size, 0);
    if (err < 0) {
        Logger::error("Failed to set period size: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set buffer size (8 periods for smoother playback)
    snd_pcm_uframes_t buffer_size = period_size * 8;
    err = snd_pcm_hw_params_set_buffer_size_near(pcm_handle_, hw_params,
                                                 &buffer_size);
    if (err < 0) {
        Logger::error("Failed to set buffer size: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Apply hardware parameters
    err = snd_pcm_hw_params(pcm_handle_, hw_params);
    if (err < 0) {
        Logger::error("Failed to apply hw params: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set software parameters for low latency
    snd_pcm_sw_params_t* sw_params;
    snd_pcm_sw_params_alloca(&sw_params);
    
    err = snd_pcm_sw_params_current(pcm_handle_, sw_params);
    if (err < 0) {
        Logger::error("Failed to get sw params: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Start playing immediately when we have any data
    // Setting to 1 means start as soon as first frame is written
    err = snd_pcm_sw_params_set_start_threshold(pcm_handle_, sw_params, 1);
    if (err < 0) {
        Logger::error("Failed to set start threshold: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Set minimum available frames to period_size
    err = snd_pcm_sw_params_set_avail_min(pcm_handle_, sw_params, period_size);
    if (err < 0) {
        Logger::error("Failed to set avail min: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Apply software parameters
    err = snd_pcm_sw_params(pcm_handle_, sw_params);
    if (err < 0) {
        Logger::error("Failed to apply sw params: " + std::string(snd_strerror(err)));
        return false;
    }
    
    // Prepare PCM for playback
    err = snd_pcm_prepare(pcm_handle_);
    if (err < 0) {
        Logger::error("Failed to prepare PCM: " + std::string(snd_strerror(err)));
        return false;
    }
    
    current_channels_ = channels;
    current_sample_rate_ = actual_rate;
    
    Logger::info("Audio configured: " + std::to_string(channels) + " channels, " +
                std::to_string(actual_rate) + " Hz, period " + 
                std::to_string(period_size) + " frames");
    
    // Don't do test write - might be interfering
    // Test write with silence to verify ALSA is working
    //std::vector<int16_t> silence(period_size * channels, 0);
    //snd_pcm_sframes_t test_frames = snd_pcm_writei(pcm_handle_, silence.data(), period_size);
    //if (test_frames < 0) {
    //    Logger::error("Test write failed: " + std::string(snd_strerror(test_frames)));
    //    return false;
    //}
    //Logger::info("Test write successful: " + std::to_string(test_frames) + " frames");
    
    return true;
}

bool ALSAAudioOutput::writeAudio(const int16_t* samples, int channels, 
                                 int num_samples, int sample_rate) {
    if (!pcm_handle_ || !samples) {
        Logger::error("No PCM handle or samples");
        return false;
    }
    
    // Sanity check parameters
    if (channels <= 0 || channels > 32 || num_samples <= 0 || num_samples > 192000 || 
        sample_rate <= 0 || sample_rate > 192000) {
        Logger::error("Invalid audio parameters: channels=" + std::to_string(channels) + 
                     ", samples=" + std::to_string(num_samples) + 
                     ", rate=" + std::to_string(sample_rate));
        return false;
    }
    
    // Reconfigure if parameters changed
    if (channels != current_channels_ || sample_rate != current_sample_rate_) {
        if (!configureHardwareParams(channels, sample_rate)) {
            return false;
        }
    }
    
    // Get the state before writing
    snd_pcm_state_t state = snd_pcm_state(pcm_handle_);
    
    if (state != SND_PCM_STATE_RUNNING && state != SND_PCM_STATE_PREPARED) {
        Logger::info("PCM state needs prepare, current state: " + std::to_string(state));
        int err = snd_pcm_prepare(pcm_handle_);
        if (err < 0) {
            Logger::error("Failed to prepare PCM: " + std::string(snd_strerror(err)));
            return false;
        }
    }
    // Check available buffer space
    snd_pcm_sframes_t avail = snd_pcm_avail(pcm_handle_);
    if (avail < 0) {
        Logger::error("Failed to check available frames: " + std::string(snd_strerror(avail)));
        // Try to recover
        snd_pcm_prepare(pcm_handle_);
        avail = snd_pcm_avail(pcm_handle_);
    }
    
    // If not enough space, wait or drop old frames
    if (avail < num_samples) {
        // Wait for space to become available
        int err = snd_pcm_wait(pcm_handle_, 100); // Wait up to 100ms
        if (err < 0) {
            Logger::warning("PCM wait failed: " + std::string(snd_strerror(err)));
        }
        avail = snd_pcm_avail(pcm_handle_);
    }
    
    // Write samples to ALSA
    snd_pcm_sframes_t frames_written = snd_pcm_writei(pcm_handle_, samples, 
                                                      num_samples);
    
    if (frames_written < 0) {
        // Handle underrun
        if (frames_written == -EPIPE) {
            Logger::warning("Audio underrun occurred");
            snd_pcm_prepare(pcm_handle_);
            // Try again
            frames_written = snd_pcm_writei(pcm_handle_, samples, num_samples);
        } else if (frames_written == -ESTRPIPE) {
            Logger::warning("Audio stream suspended");
            // Wait for resume
            while ((frames_written = snd_pcm_resume(pcm_handle_)) == -EAGAIN) {
                usleep(100000); // 100ms
            }
            if (frames_written < 0) {
                frames_written = snd_pcm_prepare(pcm_handle_);
            }
            if (frames_written >= 0) {
                // Try write again
                frames_written = snd_pcm_writei(pcm_handle_, samples, num_samples);
            }
        }
        
        if (frames_written < 0) {
            Logger::error("Failed to write audio: " + 
                         std::string(snd_strerror(frames_written)));
            return false;
        }
    }
    
    if (frames_written < num_samples) {
        // Partial write - buffer is full, will catch up on next write
    }
    
    return true;
}

// Factory function implementation
std::unique_ptr<AudioOutput> createAudioOutput() {
    return std::make_unique<ALSAAudioOutput>();
}

} // namespace display
} // namespace ndi_bridge