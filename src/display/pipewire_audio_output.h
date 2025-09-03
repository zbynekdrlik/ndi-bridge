#pragma once

#include "audio_output.h"
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <atomic>
#include <mutex>
#include <vector>

namespace ndi_bridge {
namespace display {

class PipeWireAudioOutput : public AudioOutput {
public:
    PipeWireAudioOutput();
    ~PipeWireAudioOutput() override;
    
    bool initialize() override;
    void shutdown() override;
    bool openDevice(int display_id) override;
    void closeDevice() override;
    bool isOpen() const override;
    bool writeAudio(const int16_t* samples, int channels, 
                   int num_samples, int sample_rate) override;
    
private:
    // PipeWire callbacks
    static void onProcess(void* data);
    
    // PipeWire components
    struct pw_thread_loop* loop_ = nullptr;
    struct pw_stream* stream_ = nullptr;
    
    // Stream events
    struct pw_stream_events stream_events_ = {};
    spa_hook stream_listener_ = {};
    
    // Audio ring buffer
    std::vector<int16_t> buffer_;
    size_t write_pos_ = 0;
    size_t read_pos_ = 0;
    mutable std::mutex buffer_mutex_;
    
    // Stream state
    std::atomic<bool> is_open_{false};
    
    // Fixed low-latency configuration for media-bridge
    static constexpr uint32_t QUANTUM = 256;  // ~5.3ms at 48kHz
    static constexpr uint32_t RATE = 48000;

} // namespace display
} // namespace ndi_bridge