#include "ndi_receiver.h"
#include "../common/logger.h"
#include <chrono>
#include <thread>

namespace ndi_bridge {
namespace display {

NDISource::NDISource(const NDIlib_source_t& source) {
    if (source.p_ndi_name) {
        name = source.p_ndi_name;
    }
    if (source.p_url_address) {
        url = source.p_url_address;
        // Extract IP from URL if available
        std::string url_str(source.p_url_address);
        size_t start = url_str.find("://");
        if (start != std::string::npos) {
            start += 3;
            size_t end = url_str.find(":", start);
            if (end == std::string::npos) {
                end = url_str.find("/", start);
            }
            if (end != std::string::npos) {
                ip_address = url_str.substr(start, end - start);
            }
        }
    }
}

NDIReceiver::NDIReceiver() {
    // Constructor
}

NDIReceiver::~NDIReceiver() {
    stopReceiving();
    disconnect();
    shutdown();
}

bool NDIReceiver::initialize() {
    if (initialized_) {
        return true;
    }
    
    if (!NDIlib_initialize()) {
        Logger::error("Failed to initialize NDI library");
        return false;
    }
    
    initialized_ = true;
    Logger::info("NDI library initialized for receiver");
    return true;
}

void NDIReceiver::shutdown() {
    if (!initialized_) {
        return;
    }
    
    // Ensure we're disconnected before shutting down
    if (connected_) {
        disconnect();
    }
    
    if (find_instance_) {
        NDIlib_find_destroy(find_instance_);
        find_instance_ = nullptr;
    }
    
    // Destroy NDI library (single instance, so this is safe)
    NDIlib_destroy();
    
    initialized_ = false;
    Logger::info("NDI receiver shutdown");
}

std::vector<NDISource> NDIReceiver::findSources(int timeout_ms) {
    std::vector<NDISource> sources;
    
    if (!initialized_) {
        Logger::error("NDI not initialized");
        return sources;
    }
    
    // Create finder if not exists
    if (!find_instance_) {
        NDIlib_find_create_t find_create;
        find_create.show_local_sources = true;
        find_create.p_groups = nullptr;
        find_create.p_extra_ips = nullptr;
        
        find_instance_ = NDIlib_find_create_v2(&find_create);
        if (!find_instance_) {
            Logger::error("Failed to create NDI finder");
            return sources;
        }
    }
    
    // Wait for sources
    Logger::info("Looking for NDI sources...");
    NDIlib_find_wait_for_sources(find_instance_, timeout_ms);
    
    // Get current sources
    uint32_t num_sources = 0;
    const NDIlib_source_t* p_sources = NDIlib_find_get_current_sources(find_instance_, &num_sources);
    
    Logger::info("Found " + std::to_string(num_sources) + " NDI sources");
    
    for (uint32_t i = 0; i < num_sources; i++) {
        sources.emplace_back(p_sources[i]);
        Logger::info("  - " + sources.back().name);
    }
    
    return sources;
}

bool NDIReceiver::connect(const NDISource& source) {
    return connect(source.name);
}

bool NDIReceiver::connect(const std::string& source_name) {
    if (source_name.empty()) {
        Logger::error("Empty source name");
        return false;
    }
    
    // Disconnect if already connected
    if (connected_) {
        disconnect();
    }
    
    // Find the source
    auto sources = findSources(2000);
    
    // Get current sources once
    uint32_t num_sources = 0;
    const NDIlib_source_t* p_sources = NDIlib_find_get_current_sources(find_instance_, &num_sources);
    
    // Find the matching source
    const NDIlib_source_t* target_source = nullptr;
    for (uint32_t i = 0; i < num_sources; i++) {
        if (p_sources[i].p_ndi_name && std::string(p_sources[i].p_ndi_name) == source_name) {
            target_source = &p_sources[i];
            break;
        }
    }
    
    if (!target_source) {
        Logger::error("Source not found: " + source_name);
        return false;
    }
    
    // Create receiver with a copy of the source info
    NDIlib_source_t source_copy = *target_source;
    
    NDIlib_recv_create_v3_t recv_create;
    recv_create.source_to_connect_to = source_copy;
    recv_create.p_ndi_recv_name = "NDI Display Receiver";
    recv_create.bandwidth = NDIlib_recv_bandwidth_highest;
    recv_create.allow_video_fields = false;
    recv_create.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    
    recv_instance_ = NDIlib_recv_create_v3(&recv_create);
    if (!recv_instance_) {
        Logger::error("Failed to create NDI receiver");
        return false;
    }
    
    current_source_name_ = source_name;
    connected_ = true;
    
    Logger::info("Connected to NDI source: " + source_name);
    return true;
}

void NDIReceiver::disconnect() {
    stopReceiving();
    
    if (recv_instance_) {
        NDIlib_recv_destroy(recv_instance_);
        recv_instance_ = nullptr;
    }
    
    connected_ = false;
    current_source_name_.clear();
    
    // Reset stats
    {
        std::lock_guard<std::mutex> lock(stats_mutex_);
        stats_ = Stats();
    }
    
    Logger::info("Disconnected from NDI source");
}

void NDIReceiver::startReceiving() {
    if (!connected_) {
        Logger::error("Not connected to any source");
        return;
    }
    
    receiving_ = true;
    Logger::info("Starting NDI reception");
    
    while (receiving_ && connected_) {
        NDIlib_video_frame_v2_t video_frame;
        NDIlib_audio_frame_v2_t audio_frame;
        NDIlib_metadata_frame_t metadata_frame;
        
        // Capture with 100ms timeout
        NDIlib_frame_type_e frame_type = NDIlib_recv_capture_v2(
            recv_instance_, 
            &video_frame, 
            &audio_frame, 
            &metadata_frame, 
            100
        );
        
        switch (frame_type) {
            case NDIlib_frame_type_video:
                // Update stats
                {
                    std::lock_guard<std::mutex> lock(stats_mutex_);
                    stats_.frames_received++;
                    stats_.width = video_frame.xres;
                    stats_.height = video_frame.yres;
                    stats_.fps = static_cast<float>(video_frame.frame_rate_N) / video_frame.frame_rate_D;
                }
                
                // Call callback if set
                if (video_callback_) {
                    video_callback_(video_frame);
                }
                
                // Free the frame
                NDIlib_recv_free_video_v2(recv_instance_, &video_frame);
                break;
                
            case NDIlib_frame_type_audio:
                // We ignore audio for now
                NDIlib_recv_free_audio_v2(recv_instance_, &audio_frame);
                break;
                
            case NDIlib_frame_type_metadata:
                // We ignore metadata for now
                NDIlib_recv_free_metadata(recv_instance_, &metadata_frame);
                break;
                
            case NDIlib_frame_type_error:
                Logger::error("NDI receive error");
                {
                    std::lock_guard<std::mutex> lock(stats_mutex_);
                    stats_.frames_dropped++;
                }
                break;
                
            default:
                // No data or other types
                break;
        }
    }
    
    Logger::info("NDI reception stopped");
}

void NDIReceiver::stopReceiving() {
    receiving_ = false;
}

NDIReceiver::Stats NDIReceiver::getStats() const {
    std::lock_guard<std::mutex> lock(stats_mutex_);
    return stats_;
}

} // namespace display
} // namespace ndi_bridge