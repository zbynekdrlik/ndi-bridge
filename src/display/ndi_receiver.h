#pragma once

#include <string>
#include <vector>
#include <memory>
#include <atomic>
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
    
    
    // Get raw NDI receiver instance for direct use (low latency)
    NDIlib_recv_instance_t getRecvInstance() const { return recv_instance_; }
    
private:
    NDIlib_find_instance_t find_instance_ = nullptr;
    NDIlib_recv_instance_t recv_instance_ = nullptr;
    
    bool initialized_ = false;
    bool connected_ = false;
    
    std::string current_source_name_;
};

} // namespace display
} // namespace ndi_bridge