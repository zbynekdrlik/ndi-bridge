#include "audio_processor.h"
#include "../common/logger.h"
#include <algorithm>
#include <cstring>

namespace ndi_bridge {
namespace display {

AudioProcessor::AudioProcessor() {
    // Initialize the interleaved structure
    audio_16s_interleaved_ = {};  // Value-initialize
    audio_16s_interleaved_.reference_level = 0;  // 0 dB reference level (standard)
}

AudioProcessor::~AudioProcessor() {
    // Buffer cleanup handled by unique_ptr
}

const int16_t* AudioProcessor::convertNDIAudio(const NDIlib_audio_frame_v2_t& audio_frame,
                                               int& out_channels,
                                               int& out_num_samples,
                                               int& out_sample_rate) {
    // Validate input
    if (!audio_frame.p_data || audio_frame.no_samples <= 0 || 
        audio_frame.no_channels <= 0) {
        Logger::error("Invalid audio frame");
        return nullptr;
    }
    
    // Sanity check parameters to prevent crashes
    if (audio_frame.no_channels > 32 || audio_frame.no_samples > 192000) {
        Logger::error("Audio frame parameters out of range: channels=" + 
                     std::to_string(audio_frame.no_channels) + 
                     ", samples=" + std::to_string(audio_frame.no_samples));
        return nullptr;
    }
    
    out_channels = audio_frame.no_channels;
    out_num_samples = audio_frame.no_samples;
    out_sample_rate = audio_frame.sample_rate;
    
    // Calculate required buffer size
    size_t required_size = audio_frame.no_samples * audio_frame.no_channels;
    
    // Reallocate buffer if needed
    if (buffer_size_ < required_size) {
        buffer_.reset(new int16_t[required_size]);
        buffer_size_ = required_size;
        
        Logger::info("Audio buffer resized to " + std::to_string(required_size) + " samples");
    }
    
    // Set up the interleaved structure
    audio_16s_interleaved_.p_data = buffer_.get();
    
    // Use NDI SDK utility to convert audio to 16-bit interleaved format
    // This handles both planar and interleaved input correctly
    NDIlib_util_audio_to_interleaved_16s_v2(&audio_frame, &audio_16s_interleaved_);
    
    // The conversion fills in these fields
    // audio_16s_interleaved_.sample_rate = audio_frame.sample_rate
    // audio_16s_interleaved_.no_channels = audio_frame.no_channels  
    // audio_16s_interleaved_.no_samples = audio_frame.no_samples
    // audio_16s_interleaved_.timecode = audio_frame.timecode
    
    return buffer_.get();
}

} // namespace display
} // namespace ndi_bridge