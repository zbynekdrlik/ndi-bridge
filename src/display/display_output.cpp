#include "display_output.h"
#include "../common/logger.h"

namespace ndi_bridge {
namespace display {

// Base class implementations
DisplayOutput::DisplayOutput() = default;
DisplayOutput::~DisplayOutput() = default;

// Forward declaration for DRM implementation
std::unique_ptr<DisplayOutput> createDRMDisplayOutput();

// Factory function - DRM/KMS only (optimized for Intel iGPUs)
std::unique_ptr<DisplayOutput> createDisplayOutput() {
    auto drm = createDRMDisplayOutput();
    if (!drm) {
        Logger::error("Failed to initialize DRM display output");
        return nullptr;
    }
    return drm;
}

} // namespace display
} // namespace ndi_bridge