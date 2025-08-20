#pragma once

#include <string>
#include <fstream>
#include <chrono>
#include <filesystem>
#include <unistd.h>

namespace ndi_bridge {
namespace display {

class StatusReporter {
public:
    StatusReporter(int display_id) 
        : display_id_(display_id)
        , pid_(getpid()) {
        // Ensure status directory exists
        std::filesystem::create_directories("/var/run/ndi-display");
        
        status_file_ = "/var/run/ndi-display/display-" + 
                      std::to_string(display_id) + ".status";
        temp_file_ = status_file_ + ".tmp";
    }
    
    ~StatusReporter() {
        // Remove status file on exit
        std::filesystem::remove(status_file_);
    }
    
    void update(const std::string& stream_name, 
                int width, int height,
                float fps, float bitrate_mbps,
                uint64_t frames_received,
                uint64_t frames_dropped) {
        
        auto now = std::chrono::system_clock::now();
        auto time_t = std::chrono::system_clock::to_time_t(now);
        
        // Write to temp file
        std::ofstream f(temp_file_);
        if (!f) return;
        
        f << "STREAM_NAME=\"" << stream_name << "\"\n";
        f << "DISPLAY_ID=" << display_id_ << "\n";
        f << "PID=" << pid_ << "\n";
        f << "RESOLUTION=" << width << "x" << height << "\n";
        f << "FPS=" << fps << "\n";
        f << "BITRATE=" << bitrate_mbps << "\n";
        f << "FRAMES_RECEIVED=" << frames_received << "\n";
        f << "FRAMES_DROPPED=" << frames_dropped << "\n";
        
        char time_buf[100];
        std::strftime(time_buf, sizeof(time_buf), "%Y-%m-%dT%H:%M:%S", 
                     std::localtime(&time_t));
        f << "TIMESTAMP=" << time_buf << "\n";
        
        f.close();
        
        // Atomic rename
        std::filesystem::rename(temp_file_, status_file_);
    }
    
    void clear() {
        std::filesystem::remove(status_file_);
    }
    
private:
    int display_id_;
    pid_t pid_;
    std::string status_file_;
    std::string temp_file_;
};

} // namespace display
} // namespace ndi_bridge