#include <iostream>
#include <string>
#include <vector>
#include <atomic>
#include <csignal>
#include <chrono>
#include <filesystem>
#include <fstream>

#include "ndi_receiver.h"
#include "display_output.h"
#include "audio_output.h"
#include "audio_processor.h"
#include "status_reporter.h"
#include "../common/logger.h"
#include "../common/version.h"

using namespace ndi_bridge;
using namespace ndi_bridge::display;

// Global shutdown flag with proper memory ordering
std::atomic<bool> g_shutdown(false);

void signalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        // CRITICAL: Don't call Logger from signal handler (not async-signal-safe)
        g_shutdown.store(true, std::memory_order_release);
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
    
    // First check physical display connections
    auto display = createDisplayOutput();
    std::vector<DisplayInfo> displays;
    if (display && display->initialize()) {
        displays = display->getDisplays();
        display->shutdown();
    }
    
    // Check console policy
    std::string policy_file = "/etc/media-bridge/display-policy.conf";
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
    
    // Show status for each display (up to 3 which is common for Intel iGPUs)
    // Could be made configurable if needed for systems with more displays
    const int max_displays = std::max(3, static_cast<int>(displays.size()));
    for (int i = 0; i < max_displays; i++) {
        std::cout << "Display " << i << " (HDMI-" << (i+1) << "): ";
        
        // Show physical connection status
        if (i < static_cast<int>(displays.size()) && displays[i].connected) {
            std::cout << "[Connected: " << displays[i].width << "x" << displays[i].height 
                     << " @ " << displays[i].refresh_rate << "Hz] ";
        }
        
        // Check if NDI is running on this display (try both /var/run and /tmp)
        std::string status_file = "/var/run/ndi-display/display-" + 
                                 std::to_string(i) + ".status";
        
        if (!std::filesystem::exists(status_file)) {
            // Try /tmp fallback
            status_file = "/tmp/ndi-display/display-" + 
                         std::to_string(i) + ".status";
        }
        
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
            
            std::cout << "\n";
            std::cout << "  Stream: " << stream_name << "\n";
            std::cout << "  Resolution: " << resolution << " @ " << fps << " fps\n";
            std::cout << "  Bitrate: " << bitrate << " Mbps\n";
            std::cout << "  Frames: " << frames_received << " received, " 
                     << frames_dropped << " dropped\n";
        } else if (i == console_display) {
            std::cout << "\n  Linux Console (TTY)\n";
        } else if (i < static_cast<int>(displays.size()) && displays[i].connected) {
            std::cout << "\n  No active stream\n";
        } else {
            std::cout << "[Not connected]\n";
        }
        
        // Close display info properly
        if (!(i < static_cast<int>(displays.size()) && displays[i].connected)) {
            std::cout << "\n";
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
    
    // Initialize audio output
    auto audio = createAudioOutput();
    AudioProcessor audio_processor;
    bool audio_initialized = false;
    
    if (audio && audio->initialize()) {
        if (audio->openDevice(display_id)) {
            audio_initialized = true;
            Logger::info("Audio output initialized for display " + 
                        std::to_string(display_id));
        } else {
            Logger::warning("Failed to open audio device for display " + 
                          std::to_string(display_id) + ", continuing without audio");
        }
    } else {
        Logger::warning("Failed to initialize audio system, continuing without audio");
    }
    
    // Status reporter
    StatusReporter status(display_id);
    
    // Frame statistics
    uint64_t frame_count = 0;
    uint64_t frames_dropped = 0;
    uint64_t last_frame_count = 0;
    uint64_t audio_frame_count = 0;
    int audio_channels = 0;
    int audio_sample_rate = 0;
    int status_counter = 0;
    auto start_time = std::chrono::steady_clock::now();
    auto last_status_update = start_time;
    
    Logger::info("Starting receive loop... Press Ctrl+C to stop");
    
    // Main receive loop - single threaded for low latency
    while (!g_shutdown.load(std::memory_order_acquire)) {
        NDIlib_video_frame_v2_t video_frame = {};  // CRITICAL: Must zero-initialize
        NDIlib_audio_frame_v2_t audio_frame = {};   // CRITICAL: Must zero-initialize
        NDIlib_metadata_frame_t metadata_frame = {}; // CRITICAL: Must zero-initialize
        
        // Capture with 100ms timeout
        auto recv_instance = receiver.getRecvInstance();
        if (!recv_instance) {
            Logger::error("Receiver instance lost");
            break;
        }
        
        NDIlib_frame_type_e frame_type = NDIlib_recv_capture_v2(
            recv_instance,
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
                
                // Validate frame data before displaying
                bool displayed = false;
                if (video_frame.p_data && video_frame.xres > 0 && video_frame.yres > 0) {
                    displayed = display->displayFrame(
                        video_frame.p_data,
                        video_frame.xres,
                        video_frame.yres,
                        format,
                        video_frame.line_stride_in_bytes
                    );
                } else {
                    Logger::warning("Invalid frame data received from NDI");
                }
                
                if (!displayed) {
                    frames_dropped++;
                }
                
                // Free the frame (using cached instance)
                NDIlib_recv_free_video_v2(recv_instance, &video_frame);
                
                // Update status every second (time-based)
                auto now = std::chrono::steady_clock::now();
                auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                    now - last_status_update).count();
                
                if (elapsed_ms >= 1000) {  // Update every second
                    // Calculate FPS based on frames in this interval
                    uint64_t frames_in_interval = frame_count - last_frame_count;
                    float fps = (frames_in_interval * 1000.0f) / elapsed_ms;
                    
                    // Calculate NDI network bitrate (typical NDI compression ratios)
                    // NDI uses roughly 100-150 Mbps for 1080p60, 25-50 Mbps for 1080p30
                    // This is much lower than raw data rate due to NDI compression
                    float pixels_per_sec = (float)video_frame.xres * video_frame.yres * fps;
                    // Estimate based on typical NDI compression (about 2-3 bits per pixel)
                    float bitrate_mbps = (pixels_per_sec * 2.5f) / 1000000.0f;
                    
                    status.update(stream_name, 
                                video_frame.xres, video_frame.yres,
                                fps, bitrate_mbps,
                                frame_count, frames_dropped,
                                audio_channels, audio_sample_rate, audio_frame_count);
                    
                    last_status_update = now;
                    last_frame_count = frame_count;
                    
                    // Log every 10 seconds
                    if (++status_counter >= 10) {
                        Logger::info("Frames: " + std::to_string(frame_count) + 
                                   " (" + std::to_string(fps) + " fps)");
                        status_counter = 0;
                    }
                }
                break;
            }
            
            case NDIlib_frame_type_audio: {
                // Process audio if initialized
                if (audio_initialized && audio->isOpen()) {
                    int channels, num_samples, sample_rate;
                    const int16_t* converted = audio_processor.convertNDIAudio(
                        audio_frame, channels, num_samples, sample_rate);
                    
                    if (converted) {
                        if (audio->writeAudio(converted, channels, num_samples, sample_rate)) {
                            // Update audio statistics
                            audio_frame_count++;
                            audio_channels = channels;
                            audio_sample_rate = sample_rate;
                        }
                    }
                }
                
                NDIlib_recv_free_audio_v2(recv_instance, &audio_frame);
                break;
            }
                
            case NDIlib_frame_type_metadata:
                // We ignore metadata
                NDIlib_recv_free_metadata(recv_instance, &metadata_frame);
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
    if (g_shutdown.load(std::memory_order_acquire)) {
        Logger::info("Shutdown requested...");
    }
    Logger::info("Shutting down...");
    
    // Clear display before closing
    display->clearDisplay();
    
    // Close audio if initialized
    if (audio_initialized && audio) {
        audio->closeDevice();
    }
    
    // Destructors will handle cleanup
    // display destructor calls shutdown()
    // audio destructor calls shutdown()
    // receiver destructor calls disconnect() and shutdown()
    // status destructor removes status file
    
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