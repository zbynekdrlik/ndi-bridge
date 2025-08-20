#pragma once

#include <string>
#include <map>
#include <vector>
#include <memory>
#include <thread>
#include <atomic>
#include <mutex>

#include "ndi_receiver.h"
#include "display_output.h"

namespace ndi_bridge {
namespace display {

// Represents a stream-to-display mapping
struct StreamMapping {
    std::string stream_name;
    int display_id;
    bool active;
    
    // Runtime state
    std::unique_ptr<NDIReceiver> receiver;
    std::unique_ptr<DisplayOutput> display;
    std::unique_ptr<std::thread> receive_thread;
};

class StreamManager {
public:
    StreamManager();
    ~StreamManager();
    
    // Initialize the manager
    bool initialize();
    
    // Shutdown the manager
    void shutdown();
    
    // Map a stream to a display
    bool mapStream(const std::string& stream_name, int display_id);
    
    // Unmap a display
    bool unmapDisplay(int display_id);
    
    // Get all current mappings (returns display_id -> stream_name pairs)
    std::vector<std::pair<int, std::string>> getMappings() const;
    
    // Auto-map available streams to displays
    bool autoMap();
    
    // Load/save configuration
    bool loadConfig(const std::string& path);
    bool saveConfig(const std::string& path);
    
    // Get statistics for a display
    struct DisplayStats {
        std::string stream_name;
        uint64_t frames_received;
        uint64_t frames_displayed;
        uint64_t frames_dropped;
        float fps;
        int width;
        int height;
    };
    DisplayStats getDisplayStats(int display_id) const;
    
private:
    std::map<int, StreamMapping> mappings_;
    mutable std::mutex mappings_mutex_;
    std::atomic<bool> initialized_{false};
    
    // Start receiving for a mapping
    bool startReceiving(StreamMapping& mapping);
    
    // Stop receiving for a mapping
    void stopReceiving(StreamMapping& mapping);
};

} // namespace display
} // namespace ndi_bridge