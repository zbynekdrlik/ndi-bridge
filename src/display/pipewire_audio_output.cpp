#include "pipewire_audio_output.h"
#include "../common/logger.h"
#include <spa/param/audio/format-utils.h>
#include <cstring>
#include <algorithm>

namespace ndi_bridge {
namespace display {

PipeWireAudioOutput::PipeWireAudioOutput() {
    // Initialize buffer for ~100ms at 48kHz stereo
    buffer_.resize(48000 * 2 / 10);
}

PipeWireAudioOutput::~PipeWireAudioOutput() {
    shutdown();
}

bool PipeWireAudioOutput::initialize() {
    // PipeWire is initialized when device is opened
    // This matches ALSA behavior
    return true;
}

void PipeWireAudioOutput::shutdown() {
    closeDevice();
}

void PipeWireAudioOutput::onProcess(void* data) {
    auto* self = static_cast<PipeWireAudioOutput*>(data);
    
    struct pw_buffer* b = pw_stream_dequeue_buffer(self->stream_);
    if (!b) return;
    
    struct spa_buffer* buf = b->buffer;
    if (!buf->datas[0].data) {
        pw_stream_queue_buffer(self->stream_, b);
        return;
    }
    
    int16_t* dst = static_cast<int16_t*>(buf->datas[0].data);
    uint32_t n_frames = std::min(b->requested, 
                                buf->datas[0].maxsize / (2 * sizeof(int16_t)));
    
    size_t samples_needed = n_frames * 2;  // Stereo
    
    // Read from ring buffer
    {
        std::lock_guard<std::mutex> lock(self->buffer_mutex_);
        
        size_t available = (self->write_pos_ >= self->read_pos_) ?
                          (self->write_pos_ - self->read_pos_) :
                          (self->buffer_.size() - self->read_pos_ + self->write_pos_);
        
        size_t to_read = std::min(samples_needed, available);
        
        for (size_t i = 0; i < to_read; ++i) {
            dst[i] = self->buffer_[self->read_pos_];
            self->read_pos_ = (self->read_pos_ + 1) % self->buffer_.size();
        }
        
        // Fill rest with silence
        if (to_read < samples_needed) {
            std::memset(dst + to_read, 0, (samples_needed - to_read) * sizeof(int16_t));
        }
    }
    
    buf->datas[0].chunk->offset = 0;
    buf->datas[0].chunk->stride = 2 * sizeof(int16_t);  // Stereo
    buf->datas[0].chunk->size = n_frames * 2 * sizeof(int16_t);
    
    pw_stream_queue_buffer(self->stream_, b);
}

bool PipeWireAudioOutput::openDevice(int display_id) {
    if (is_open_) {
        closeDevice();
    }
    
    current_display_id_ = display_id;
    
    // Initialize PipeWire
    pw_init(nullptr, nullptr);
    
    // Create main loop
    loop_ = pw_thread_loop_new("ndi-display", nullptr);
    if (!loop_) {
        Logger::getInstance().error("Failed to create PipeWire loop");
        return false;
    }
    
    pw_thread_loop_start(loop_);
    pw_thread_loop_lock(loop_);
    
    // Create stream directly connected to default output
    struct pw_properties* props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Playback",
        PW_KEY_MEDIA_ROLE, "Movie",
        PW_KEY_NODE_NAME, "ndi-display",
        PW_KEY_NODE_LATENCY, "256/48000",  // ~5.3ms
        nullptr
    );
    
    stream_ = pw_stream_new_simple(
        pw_thread_loop_get_loop(loop_),
        "ndi-display",
        props,
        &stream_events_,
        this
    );
    
    if (!stream_) {
        Logger::getInstance().error("Failed to create PipeWire stream");
        pw_thread_loop_unlock(loop_);
        shutdown();
        return false;
    }
    
    // Set up stream events - only process callback needed
    stream_events_.version = PW_VERSION_STREAM_EVENTS;
    stream_events_.process = onProcess;
    
    pw_stream_add_listener(stream_, &stream_listener_, &stream_events_, this);
    
    // Audio format: 48kHz stereo S16
    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    
    struct spa_audio_info_raw info = {
        .format = SPA_AUDIO_FORMAT_S16,
        .channels = 2,
        .rate = RATE
    };
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;
    
    const struct spa_pod* params[1];
    params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);
    
    // Connect with low latency flags
    int res = pw_stream_connect(
        stream_,
        PW_DIRECTION_OUTPUT,
        PW_ID_ANY,
        static_cast<pw_stream_flags>(
            PW_STREAM_FLAG_AUTOCONNECT |
            PW_STREAM_FLAG_MAP_BUFFERS |
            PW_STREAM_FLAG_RT_PROCESS
        ),
        params, 1
    );
    
    if (res < 0) {
        Logger::getInstance().error("Failed to connect PipeWire stream");
        pw_stream_destroy(stream_);
        stream_ = nullptr;
        pw_thread_loop_unlock(loop_);
        shutdown();
        return false;
    }
    
    pw_thread_loop_unlock(loop_);
    
    // Clear buffer
    write_pos_ = 0;
    read_pos_ = 0;
    is_open_ = true;
    
    Logger::getInstance().info("PipeWire audio output opened for display {}", display_id);
    return true;
}

void PipeWireAudioOutput::closeDevice() {
    if (stream_) {
        pw_thread_loop_lock(loop_);
        pw_stream_destroy(stream_);
        stream_ = nullptr;
        pw_thread_loop_unlock(loop_);
    }
    
    if (loop_) {
        pw_thread_loop_stop(loop_);
        pw_thread_loop_destroy(loop_);
        loop_ = nullptr;
    }
    
    is_open_ = false;
    current_display_id_ = -1;
    
    pw_deinit();
}

bool PipeWireAudioOutput::isOpen() const {
    return is_open_;
}

bool PipeWireAudioOutput::writeAudio(const int16_t* samples, int channels,
                                    int num_samples, int sample_rate) {
    if (!is_open_) {
        return false;
    }
    
    // Convert to stereo if needed
    std::vector<int16_t> stereo_samples;
    const int16_t* write_samples = samples;
    int write_count = num_samples * 2;
    
    if (channels == 1) {
        // Mono to stereo
        stereo_samples.resize(num_samples * 2);
        for (int i = 0; i < num_samples; ++i) {
            stereo_samples[i * 2] = samples[i];
            stereo_samples[i * 2 + 1] = samples[i];
        }
        write_samples = stereo_samples.data();
    } else if (channels > 2) {
        // Just take first 2 channels
        stereo_samples.resize(num_samples * 2);
        for (int i = 0; i < num_samples; ++i) {
            stereo_samples[i * 2] = samples[i * channels];
            stereo_samples[i * 2 + 1] = samples[i * channels + 1];
        }
        write_samples = stereo_samples.data();
    }
    
    // Write to ring buffer
    {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        
        for (int i = 0; i < write_count; ++i) {
            buffer_[write_pos_] = write_samples[i];
            write_pos_ = (write_pos_ + 1) % buffer_.size();
            
            // Handle overflow by moving read pointer
            if (write_pos_ == read_pos_) {
                read_pos_ = (read_pos_ + 1) % buffer_.size();
            }
        }
    }
    
    return true;
}

} // namespace display
} // namespace ndi_bridge