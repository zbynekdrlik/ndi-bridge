#pragma once

#include <mutex>
#include <Processing.NDI.Lib.h>

namespace ndi_bridge {
namespace display {

// Singleton class to manage NDI library lifecycle
class NDIManager {
public:
    static NDIManager& getInstance() {
        static NDIManager instance;
        return instance;
    }
    
    bool initialize() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (ref_count_ == 0) {
            if (!NDIlib_initialize()) {
                return false;
            }
        }
        ref_count_++;
        return true;
    }
    
    void shutdown() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (ref_count_ > 0) {
            ref_count_--;
            if (ref_count_ == 0) {
                NDIlib_destroy();
            }
        }
    }
    
    NDIManager(const NDIManager&) = delete;
    NDIManager& operator=(const NDIManager&) = delete;
    
private:
    NDIManager() = default;
    ~NDIManager() {
        if (ref_count_ > 0) {
            NDIlib_destroy();
        }
    }
    
    std::mutex mutex_;
    int ref_count_ = 0;
};

} // namespace display
} // namespace ndi_bridge