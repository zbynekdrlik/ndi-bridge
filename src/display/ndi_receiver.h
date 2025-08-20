#pragma once

#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <atomic>
#include <mutex>
#include <Processing.NDI.Lib.h>

namespace ndi_bridge {
namespace display {

// Structure to hold NDI source information
struct NDISource {
    std::string name;
    std::string url;
    std::string ip_address;
    
    NDISource() = default;
    NDISource(const NDIlib_source_t& source);
};

// Callback for when a video frame is received
using VideoFrameCallback = std::function<void(const NDIlib_video_frame_v2_t&)>;

class NDIReceiver {
public:
    NDIReceiver();
    ~NDIReceiver();
    
    // Initialize NDI library
    bool initialize();
    
    // Shutdown NDI library
    void shutdown();
    
    // Find available NDI sources on the network
    std::vector<NDISource> findSources(int timeout_ms = 5000);
    
    // Connect to an NDI source
    bool connect(const NDISource& source);
    bool connect(const std::string& source_name);
    
    // Disconnect from current source
    void disconnect();
    
    // Check if connected
    bool isConnected() const { return recv_instance_ != nullptr && connected_; }
    
    // Get current source name
    std::string getCurrentSourceName() const { return current_source_name_; }
    
    // Set callback for video frames
    void setVideoFrameCallback(VideoFrameCallback callback) { video_callback_ = callback; }
    
    // Start receiving (blocking call - run in separate thread)
    void startReceiving();
    
    // Stop receiving
    void stopReceiving();
    
    // Get statistics
    struct Stats {
        uint64_t frames_received = 0;
        uint64_t frames_dropped = 0;
        int width = 0;
        int height = 0;
        float fps = 0.0f;
    };
    Stats getStats() const;
    
    // Get raw NDI receiver instance for direct use (low latency)
    NDIlib_recv_instance_t getRecvInstance() const { return recv_instance_; }
    
private:
    NDIlib_find_instance_t find_instance_ = nullptr;
    NDIlib_recv_instance_t recv_instance_ = nullptr;
    
    bool initialized_ = false;
    bool connected_ = false;
    std::atomic<bool> receiving_{false};
    
    std::string current_source_name_;
    VideoFrameCallback video_callback_;
    
    mutable std::mutex stats_mutex_;
    Stats stats_;
};

} // namespace display
} // namespace ndi_bridge