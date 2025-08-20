#include "stream_manager.h"
#include "../common/logger.h"
#include <fstream>
#include <algorithm>

namespace ndi_bridge {
namespace display {

StreamManager::StreamManager() {
    // Constructor
}

StreamManager::~StreamManager() {
    shutdown();
}

bool StreamManager::initialize() {
    if (initialized_) {
        return true;
    }
    
    initialized_ = true;
    Logger::info("Stream manager initialized");
    return true;
}

void StreamManager::shutdown() {
    if (!initialized_) {
        return;
    }
    
    // Stop all active streams
    std::lock_guard<std::mutex> lock(mappings_mutex_);
    for (auto& [display_id, mapping] : mappings_) {
        if (mapping.active) {
            stopReceiving(mapping);
        }
    }
    mappings_.clear();
    
    initialized_ = false;
    Logger::info("Stream manager shutdown");
}

bool StreamManager::mapStream(const std::string& stream_name, int display_id) {
    std::lock_guard<std::mutex> lock(mappings_mutex_);
    
    // Check if display is already mapped
    auto it = mappings_.find(display_id);
    if (it != mappings_.end() && it->second.active) {
        Logger::warning("Display " + std::to_string(display_id) + " already mapped");
        stopReceiving(it->second);
        mappings_.erase(it);
    }
    
    // Create new mapping directly in the map
    StreamMapping& mapping = mappings_[display_id];
    mapping.stream_name = stream_name;
    mapping.display_id = display_id;
    mapping.active = false;
    
    // Start receiving with the mapping now in its final location
    if (!startReceiving(mapping)) {
        Logger::error("Failed to start stream mapping");
        mappings_.erase(display_id);
        return false;
    }
    
    Logger::info("Mapped stream '" + stream_name + "' to display " + std::to_string(display_id));
    return true;
}

bool StreamManager::unmapDisplay(int display_id) {
    std::lock_guard<std::mutex> lock(mappings_mutex_);
    
    auto it = mappings_.find(display_id);
    if (it == mappings_.end()) {
        Logger::warning("Display " + std::to_string(display_id) + " not mapped");
        return false;
    }
    
    stopReceiving(it->second);
    mappings_.erase(it);
    
    Logger::info("Unmapped display " + std::to_string(display_id));
    return true;
}

std::vector<std::pair<int, std::string>> StreamManager::getMappings() const {
    std::lock_guard<std::mutex> lock(mappings_mutex_);
    std::vector<std::pair<int, std::string>> result;
    for (const auto& [display_id, mapping] : mappings_) {
        result.push_back({display_id, mapping.stream_name});
    }
    return result;
}

bool StreamManager::autoMap() {
    Logger::info("Starting auto-mapping of NDI streams to displays");
    
    // Find available NDI sources
    NDIReceiver temp_receiver;
    if (!temp_receiver.initialize()) {
        Logger::error("Failed to initialize NDI for auto-mapping");
        return false;
    }
    
    auto sources = temp_receiver.findSources(5000);
    if (sources.empty()) {
        Logger::warning("No NDI sources found for auto-mapping");
        return false;
    }
    
    // Get available displays
    auto display = createDisplayOutput();
    if (!display || !display->initialize()) {
        Logger::error("Failed to initialize display system for auto-mapping");
        return false;
    }
    
    auto displays = display->getDisplays();
    display->shutdown();
    
    // Map up to 3 streams to displays
    int mapped_count = 0;
    int max_displays = std::min(3, static_cast<int>(displays.size()));
    int max_sources = std::min(max_displays, static_cast<int>(sources.size()));
    
    for (int i = 0; i < max_sources; i++) {
        if (mapStream(sources[i].name, i)) {
            Logger::info("Auto-mapped '" + sources[i].name + "' to display " + std::to_string(i));
            mapped_count++;
        } else {
            Logger::warning("Failed to auto-map '" + sources[i].name + "' to display " + std::to_string(i));
        }
    }
    
    Logger::info("Auto-mapping complete: " + std::to_string(mapped_count) + " streams mapped");
    return mapped_count > 0;
}

bool StreamManager::loadConfig(const std::string& path) {
    // TODO: Implement config loading with JSON
    // Will need to add jsoncpp dependency when implementing this feature
    Logger::info("Config loading not yet implemented");
    return false;
}

bool StreamManager::saveConfig(const std::string& path) {
    // TODO: Implement config saving with JSON
    // Will need to add jsoncpp dependency when implementing this feature
    Logger::info("Config saving not yet implemented");
    return false;
}

StreamManager::DisplayStats StreamManager::getDisplayStats(int display_id) const {
    DisplayStats stats;
    
    std::lock_guard<std::mutex> lock(mappings_mutex_);
    auto it = mappings_.find(display_id);
    if (it != mappings_.end() && it->second.receiver) {
        stats.stream_name = it->second.stream_name;
        auto recv_stats = it->second.receiver->getStats();
        stats.frames_received = recv_stats.frames_received;
        stats.frames_displayed = recv_stats.frames_received; // TODO: Track separately
        stats.frames_dropped = recv_stats.frames_dropped;
        stats.fps = recv_stats.fps;
        stats.width = recv_stats.width;
        stats.height = recv_stats.height;
    }
    
    return stats;
}

bool StreamManager::startReceiving(StreamMapping& mapping) {
    // Create receiver
    mapping.receiver = std::make_unique<NDIReceiver>();
    if (!mapping.receiver->initialize()) {
        Logger::error("Failed to initialize receiver");
        return false;
    }
    
    // Connect to stream
    if (!mapping.receiver->connect(mapping.stream_name)) {
        Logger::error("Failed to connect to stream: " + mapping.stream_name);
        return false;
    }
    
    // Create display output
    mapping.display = createDisplayOutput();
    if (!mapping.display || !mapping.display->initialize()) {
        Logger::error("Failed to initialize display");
        return false;
    }
    
    // Open display
    if (!mapping.display->openDisplay(mapping.display_id)) {
        Logger::error("Failed to open display " + std::to_string(mapping.display_id));
        return false;
    }
    
    // Capture display pointer for callback (safe because we control its lifetime)
    auto* display_ptr = mapping.display.get();
    
    // Set up frame callback
    mapping.receiver->setVideoFrameCallback(
        [display_ptr](const NDIlib_video_frame_v2_t& frame) {
            if (display_ptr) {
                display_ptr->displayFrame(
                    frame.p_data,
                    frame.xres,
                    frame.yres,
                    PixelFormat::BGRA,
                    frame.line_stride_in_bytes
                );
            }
        }
    );
    
    // Capture receiver pointer for thread
    auto* receiver_ptr = mapping.receiver.get();
    
    // Start receive thread
    mapping.receive_thread = std::make_unique<std::thread>(
        [receiver_ptr]() {
            if (receiver_ptr) {
                receiver_ptr->startReceiving();
            }
        }
    );
    
    mapping.active = true;
    return true;
}

void StreamManager::stopReceiving(StreamMapping& mapping) {
    if (!mapping.active) {
        return;
    }
    
    // Stop receiver
    if (mapping.receiver) {
        mapping.receiver->stopReceiving();
    }
    
    // Wait for thread
    if (mapping.receive_thread && mapping.receive_thread->joinable()) {
        mapping.receive_thread->join();
    }
    
    // Clear display
    if (mapping.display) {
        mapping.display->clearDisplay();
        mapping.display->closeDisplay();
    }
    
    // Clean up
    mapping.receiver.reset();
    mapping.display.reset();
    mapping.receive_thread.reset();
    mapping.active = false;
}

} // namespace display
} // namespace ndi_bridge