#include "stream_manager.h"
#include "../common/logger.h"
#include <fstream>

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
    }
    
    // Create new mapping
    StreamMapping mapping;
    mapping.stream_name = stream_name;
    mapping.display_id = display_id;
    mapping.active = false;
    
    // Start receiving
    if (!startReceiving(mapping)) {
        Logger::error("Failed to start stream mapping");
        return false;
    }
    
    mappings_[display_id] = std::move(mapping);
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
    // TODO: Implement auto-mapping logic
    Logger::info("Auto-mapping not yet implemented");
    return false;
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
    
    // Set up frame callback
    mapping.receiver->setVideoFrameCallback(
        [&mapping](const NDIlib_video_frame_v2_t& frame) {
            if (mapping.display) {
                mapping.display->displayFrame(
                    frame.p_data,
                    frame.xres,
                    frame.yres,
                    PixelFormat::BGRA,
                    frame.line_stride_in_bytes
                );
            }
        }
    );
    
    // Start receive thread
    mapping.receive_thread = std::make_unique<std::thread>(
        [&mapping]() {
            mapping.receiver->startReceiving();
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