#include "audio_output.h"
#include "pipewire_audio_output.h"

namespace ndi_bridge {
namespace display {

// Factory function implementation - PipeWire only for simplicity
std::unique_ptr<AudioOutput> createAudioOutput() {
    auto pipewire = std::make_unique<PipeWireAudioOutput>();
    if (!pipewire->initialize()) {
        return nullptr;
    }
    return pipewire;
}

} // namespace display
} // namespace ndi_bridge