#include <iostream>
#include <string>
#include <vector>
#include <atomic>
#include <csignal>
#include <cstring>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "ndi_receiver.h"
#include "display_output.h"
#include "status_reporter.h"
#include "../common/logger.h"
#include "../common/version.h"

using namespace ndi_bridge;
using namespace ndi_bridge::display;

// Global shutdown flag
std::atomic<bool> g_shutdown(false);

void signalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        Logger::info("Shutdown requested...");
        g_shutdown = true;
    }
}

void printUsage(const char* program) {
    std::cout << "NDI Display - Single stream to display receiver\n";
    std::cout << "Version: " << NDI_BRIDGE_VERSION << "\n\n";
    std::cout << "Usage:\n";
    std::cout << "  " << program << " <stream_name> <display_id>  # Receive and display\n";
    std::cout << "  " << program << " list                        # List available NDI streams\n";
    std::cout << "  " << program << " displays                    # List available displays\n";
    std::cout << "  " << program << " status                      # Show all displays status\n";
    std::cout << "\nExamples:\n";
    std::cout << "  " << program << " \"Camera 1\" 0                # Show Camera 1 on display 0\n";
    std::cout << "  " << program << " list\n";
}

int listStreams() {
    NDIReceiver receiver;
    if (!receiver.initialize()) {
        Logger::error("Failed to initialize NDI");
        return 1;
    }
    
    std::cout << "Searching for NDI sources...\n";
    auto sources = receiver.findSources(5000);
    
    if (sources.empty()) {
        std::cout << "No NDI sources found\n";
    } else {
        std::cout << "\nAvailable NDI sources:\n";
        std::cout << "----------------------\n";
        for (size_t i = 0; i < sources.size(); i++) {
            std::cout << i << ": " << sources[i].name;
            if (!sources[i].ip_address.empty()) {
                std::cout << " (" << sources[i].ip_address << ")";
            }
            std::cout << "\n";
        }
    }
    
    receiver.shutdown();
    return 0;
}

int listDisplays() {
    auto display = createDisplayOutput();
    if (!display || !display->initialize()) {
        Logger::error("Failed to initialize display system");
        return 1;
    }
    
    auto displays = display->getDisplays();
    
    std::cout << "\nAvailable displays:\n";
    std::cout << "------------------\n";
    for (const auto& disp : displays) {
        std::cout << "Display " << disp.id << ": " << disp.connector;
        
        // Check if console is active on this display
        std::string vtcon_path = "/sys/class/vtconsole/vtcon" + 
                                 std::to_string(disp.id) + "/bind";
        bool console_active = false;
        if (std::filesystem::exists(vtcon_path)) {
            std::ifstream f(vtcon_path);
            std::string value;
            if (f >> value && value == "1") {
                console_active = true;
            }
        }
        
        if (disp.connected) {
            std::cout << " [" << disp.width << "x" << disp.height 
                     << " @ " << disp.refresh_rate << "Hz]";
            if (console_active) {
                std::cout << " *CONSOLE*";
            }
        } else {
            std::cout << " [Not connected]";
        }
        std::cout << "\n";
    }
    
    display->shutdown();
    return 0;
}

int showStatus() {
    std::cout << "NDI Display System Status\n";
    std::cout << "=========================\n\n";
    
    // Check console policy
    std::string policy_file = "/etc/ndi-bridge/display-policy.conf";
    int console_display = 0;
    if (std::filesystem::exists(policy_file)) {
        std::ifstream f(policy_file);
        std::string line;
        while (std::getline(f, line)) {
            if (line.find("CONSOLE_DISPLAY=") == 0) {
                console_display = std::stoi(line.substr(16));
            }
        }
    }
    
    // Show status for each display
    for (int i = 0; i < 3; i++) {
        std::cout << "Display " << i << " (HDMI-" << (i+1) << "): ";
        
        // Check if NDI is running on this display
        std::string status_file = "/var/run/ndi-display/display-" + 
                                 std::to_string(i) + ".status";
        
        if (std::filesystem::exists(status_file)) {
            // Parse status file
            std::ifstream f(status_file);
            std::string line;
            std::string stream_name, resolution, fps, bitrate;
            uint64_t frames_received = 0, frames_dropped = 0;
            
            while (std::getline(f, line)) {
                if (line.find("STREAM_NAME=") == 0) {
                    stream_name = line.substr(12);
                    // Remove quotes if present
                    if (!stream_name.empty() && stream_name[0] == '"') {
                        stream_name.erase(0, 1);
                    }
                    if (!stream_name.empty() && stream_name.back() == '"') {
                        stream_name.pop_back();
                    }
                } else if (line.find("RESOLUTION=") == 0) {
                    resolution = line.substr(11);
                } else if (line.find("FPS=") == 0) {
                    fps = line.substr(4);
                } else if (line.find("BITRATE=") == 0) {
                    bitrate = line.substr(8);
                } else if (line.find("FRAMES_RECEIVED=") == 0) {
                    frames_received = std::stoull(line.substr(16));
                } else if (line.find("FRAMES_DROPPED=") == 0) {
                    frames_dropped = std::stoull(line.substr(15));
                }
            }
            
            std::cout << stream_name << "\n";
            std::cout << "  Resolution: " << resolution << " @ " << fps << " fps\n";
            std::cout << "  Bitrate: " << bitrate << " Mbps\n";
            std::cout << "  Frames: " << frames_received << " received, " 
                     << frames_dropped << " dropped\n";
        } else if (i == console_display) {
            std::cout << "Linux Console (TTY)\n";
        } else {
            std::cout << "Not active\n";
        }
        std::cout << "\n";
    }
    
    std::cout << "Console Policy: Display " << console_display 
              << " reserved for console\n";
    std::cout << "Emergency Access: SSH or Ctrl+Alt+F1\n";
    
    return 0;
}

int receiveAndDisplay(const std::string& stream_name, int display_id) {
    // Check if console is active on this display
    std::string vtcon_path = "/sys/class/vtconsole/vtcon" + 
                            std::to_string(display_id) + "/bind";
    if (std::filesystem::exists(vtcon_path)) {
        std::ifstream f(vtcon_path);
        std::string value;
        if (f >> value && value == "1") {
            Logger::error("Console is active on display " + std::to_string(display_id));
            Logger::error("Run: ndi-display-config " + std::to_string(display_id) + 
                         " to configure this display");
            return 1;
        }
    }
    
    // Initialize receiver
    NDIReceiver receiver;
    if (!receiver.initialize()) {
        Logger::error("Failed to initialize NDI");
        return 1;
    }
    
    // Connect to stream
    Logger::info("Connecting to '" + stream_name + "'...");
    if (!receiver.connect(stream_name)) {
        Logger::error("Failed to connect to stream: " + stream_name);
        return 1;
    }
    
    // Initialize display
    auto display = createDisplayOutput();
    if (!display || !display->initialize()) {
        Logger::error("Failed to initialize display system");
        return 1;
    }
    
    // Open display
    if (!display->openDisplay(display_id)) {
        Logger::error("Failed to open display " + std::to_string(display_id));
        return 1;
    }
    
    auto disp_info = display->getCurrentDisplay();
    Logger::info("Displaying on " + disp_info.connector + 
                " (" + std::to_string(disp_info.width) + "x" + 
                std::to_string(disp_info.height) + ")");
    
    // Status reporter
    StatusReporter status(display_id);
    
    // Frame statistics
    uint64_t frame_count = 0;
    uint64_t frames_dropped = 0;
    auto start_time = std::chrono::steady_clock::now();
    auto last_status_update = start_time;
    
    Logger::info("Starting receive loop... Press Ctrl+C to stop");
    
    // Main receive loop - single threaded for low latency
    while (!g_shutdown) {
        NDIlib_video_frame_v2_t video_frame;
        NDIlib_audio_frame_v2_t audio_frame;
        NDIlib_metadata_frame_t metadata_frame;
        
        // Capture with 100ms timeout
        NDIlib_frame_type_e frame_type = NDIlib_recv_capture_v2(
            receiver.getRecvInstance(),
            &video_frame,
            &audio_frame,
            &metadata_frame,
            100
        );
        
        switch (frame_type) {
            case NDIlib_frame_type_video: {
                frame_count++;
                
                // Display the frame directly - no queuing for lowest latency
                // NDI typically provides BGRA/BGRX format when we request it
                PixelFormat format = PixelFormat::BGRA;
                
                // Check actual format if needed
                switch (video_frame.FourCC) {
                    case NDIlib_FourCC_type_BGRA:
                    case NDIlib_FourCC_type_BGRX:
                        format = PixelFormat::BGRA;
                        break;
                    case NDIlib_FourCC_type_UYVY:
                    case NDIlib_FourCC_type_UYVA:
                        format = PixelFormat::UYVY;
                        break;
                    default:
                        // Default to BGRA as we requested it
                        format = PixelFormat::BGRA;
                        break;
                }
                
                bool displayed = display->displayFrame(
                    video_frame.p_data,
                    video_frame.xres,
                    video_frame.yres,
                    format,
                    video_frame.line_stride_in_bytes
                );
                
                if (!displayed) {
                    frames_dropped++;
                }
                
                // Free the frame
                NDIlib_recv_free_video_v2(receiver.getRecvInstance(), &video_frame);
                
                // Update status every 30 frames (roughly 1 second at 30fps)
                if (frame_count % 30 == 0) {
                    auto now = std::chrono::steady_clock::now();
                    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now - last_status_update).count();
                    
                    if (elapsed > 0) {
                        float fps = 30.0f * 1000.0f / elapsed;
                        // Calculate actual data size, not including padding
                        int bytes_per_pixel = 4; // BGRA is 4 bytes
                        float bitrate_mbps = (video_frame.xres * bytes_per_pixel * 
                                            video_frame.yres * fps * 8) / 1000000.0f;
                        
                        status.update(stream_name, 
                                    video_frame.xres, video_frame.yres,
                                    fps, bitrate_mbps,
                                    frame_count, frames_dropped);
                        
                        last_status_update = now;
                        
                        // Log periodically
                        if (frame_count % 300 == 0) {
                            Logger::info("Frames: " + std::to_string(frame_count) + 
                                       " (" + std::to_string(fps) + " fps)");
                        }
                    }
                }
                break;
            }
            
            case NDIlib_frame_type_audio:
                // We ignore audio
                NDIlib_recv_free_audio_v2(receiver.getRecvInstance(), &audio_frame);
                break;
                
            case NDIlib_frame_type_metadata:
                // We ignore metadata
                NDIlib_recv_free_metadata(receiver.getRecvInstance(), &metadata_frame);
                break;
                
            case NDIlib_frame_type_error:
                Logger::error("NDI receive error");
                frames_dropped++;
                break;
                
            case NDIlib_frame_type_none:
                // Timeout - normal, just continue
                break;
                
            default:
                // Other frame types we don't handle
                break;
        }
    }
    
    // Clean shutdown
    Logger::info("Shutting down...");
    display->clearDisplay();
    display->closeDisplay();
    display->shutdown();
    receiver.disconnect();
    receiver.shutdown();
    status.clear();
    
    Logger::info("Total frames: " + std::to_string(frame_count) + 
               ", dropped: " + std::to_string(frames_dropped));
    
    return 0;
}

int main(int argc, char* argv[]) {
    // Set up signal handlers
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);
    
    // Parse command line
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }
    
    std::string command = argv[1];
    
    // Single argument commands
    if (command == "list") {
        return listStreams();
    }
    else if (command == "displays") {
        return listDisplays();
    }
    else if (command == "status") {
        return showStatus();
    }
    else if (command == "--help" || command == "-h") {
        printUsage(argv[0]);
        return 0;
    }
    
    // Main operation: receive and display
    if (argc == 3) {
        std::string stream_name = argv[1];
        int display_id;
        
        try {
            display_id = std::stoi(argv[2]);
        } catch (...) {
            std::cerr << "Error: Invalid display ID\n";
            printUsage(argv[0]);
            return 1;
        }
        
        if (display_id < 0 || display_id > 2) {
            std::cerr << "Error: Display ID must be 0, 1, or 2\n";
            return 1;
        }
        
        return receiveAndDisplay(stream_name, display_id);
    }
    
    std::cerr << "Error: Invalid arguments\n";
    printUsage(argv[0]);
    return 1;
}