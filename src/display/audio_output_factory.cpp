#include "audio_output.h"
#include "pipewire_audio_output.h"
#include "../common/logger.h"

namespace ndi_bridge {
namespace display {

// Factory function implementation - PipeWire only for simplicity
std::unique_ptr<AudioOutput> createAudioOutput() {
    Logger::getInstance().info("Creating PipeWire audio backend");
    
    auto pipewire = std::make_unique<PipeWireAudioOutput>();
    if (!pipewire->initialize()) {
        Logger::getInstance().error("Failed to initialize PipeWire audio backend");
        return nullptr;
    }
    
    Logger::getInstance().info("Successfully initialized PipeWire audio backend");
    return pipewire;
}

} // namespace display
} // namespace ndi_bridge