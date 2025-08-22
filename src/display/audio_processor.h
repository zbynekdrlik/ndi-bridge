#pragma once

#include <vector>
#include <cstdint>
#include <memory>
#include <Processing.NDI.Lib.h>
#include <Processing.NDI.utilities.h>

namespace ndi_bridge {
namespace display {

class AudioProcessor {
public:
    AudioProcessor();
    ~AudioProcessor();
    
    // Convert NDI audio frame to interleaved S16_LE format using NDI SDK utilities
    // Returns pointer to converted samples and sets output parameters
    // Returns nullptr if conversion fails
    const int16_t* convertNDIAudio(const NDIlib_audio_frame_v2_t& audio_frame,
                                   int& out_channels,
                                   int& out_num_samples,
                                   int& out_sample_rate);
    
private:
    // NDI audio frame structure for conversion
    NDIlib_audio_frame_interleaved_16s_t audio_16s_interleaved_;
    
    // Buffer management
    std::unique_ptr<int16_t[]> buffer_;
    size_t buffer_size_ = 0;
};

} // namespace display
} // namespace ndi_bridge