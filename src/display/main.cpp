#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <csignal>
#include <cstring>
#include <memory>
#include <map>

#include "ndi_receiver.h"
#include "display_output.h"
#include "stream_manager.h"
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
    std::cout << "NDI Display - Show NDI streams on HDMI outputs\n";
    std::cout << "Version: " << NDI_BRIDGE_VERSION << "\n\n";
    std::cout << "Usage:\n";
    std::cout << "  " << program << " list                        # List available NDI streams\n";
    std::cout << "  " << program << " displays                    # List available displays\n";
    std::cout << "  " << program << " show <stream> <display>     # Show stream on display\n";
    std::cout << "  " << program << " stop <display>              # Stop playback on display\n";
    std::cout << "  " << program << " status                      # Show current mappings\n";
    std::cout << "  " << program << " auto                        # Auto-map first 3 streams to displays\n";
    std::cout << "\nExamples:\n";
    std::cout << "  " << program << " list\n";
    std::cout << "  " << program << " show \"Camera 1\" 0\n";
    std::cout << "  " << program << " stop 0\n";
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
        if (disp.connected) {
            std::cout << " [" << disp.width << "x" << disp.height 
                     << " @ " << disp.refresh_rate << "Hz]";
            if (disp.active) {
                std::cout << " *ACTIVE*";
            }
        } else {
            std::cout << " [Not connected]";
        }
        std::cout << "\n";
    }
    
    return 0;
}

int showStream(const std::string& stream_name, int display_id) {
    // Initialize receiver
    NDIReceiver receiver;
    if (!receiver.initialize()) {
        Logger::error("Failed to initialize NDI");
        return 1;
    }
    
    // Find and connect to source
    std::cout << "Connecting to '" << stream_name << "'...\n";
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
    std::cout << "Displaying on " << disp_info.connector 
              << " (" << disp_info.width << "x" << disp_info.height << ")\n";
    
    // Set up video frame callback
    receiver.setVideoFrameCallback(
        [&display](const NDIlib_video_frame_v2_t& frame) {
            // Display the frame
            display->displayFrame(
                frame.p_data,
                frame.xres,
                frame.yres,
                PixelFormat::BGRA,
                frame.line_stride_in_bytes
            );
        }
    );
    
    // Start receiving in separate thread
    std::thread receive_thread([&receiver]() {
        receiver.startReceiving();
    });
    
    std::cout << "Streaming... Press Ctrl+C to stop\n";
    
    // Main loop
    while (!g_shutdown) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        
        // Print stats periodically
        auto stats = receiver.getStats();
        if (stats.frames_received % 60 == 0 && stats.frames_received > 0) {
            Logger::info("Frames: " + std::to_string(stats.frames_received) + 
                        " (" + std::to_string(stats.fps) + " fps)");
        }
    }
    
    // Clean shutdown
    receiver.stopReceiving();
    receive_thread.join();
    display->clearDisplay();
    
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
    
    if (command == "list") {
        return listStreams();
    }
    else if (command == "displays") {
        return listDisplays();
    }
    else if (command == "show") {
        if (argc != 4) {
            std::cerr << "Usage: " << argv[0] << " show <stream> <display>\n";
            return 1;
        }
        std::string stream = argv[2];
        int display = std::stoi(argv[3]);
        return showStream(stream, display);
    }
    else if (command == "stop") {
        if (argc != 3) {
            std::cerr << "Usage: " << argv[0] << " stop <display>\n";
            return 1;
        }
        // TODO: Implement stop functionality with stream manager
        std::cout << "Stop functionality not yet implemented\n";
        return 0;
    }
    else if (command == "status") {
        // TODO: Implement status with stream manager
        std::cout << "Status functionality not yet implemented\n";
        return 0;
    }
    else if (command == "auto") {
        // TODO: Implement auto-mapping
        std::cout << "Auto-mapping functionality not yet implemented\n";
        return 0;
    }
    else if (command == "--help" || command == "-h") {
        printUsage(argv[0]);
        return 0;
    }
    else {
        std::cerr << "Unknown command: " << command << "\n";
        printUsage(argv[0]);
        return 1;
    }
}