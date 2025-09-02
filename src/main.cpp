#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <csignal>
#include <cstring>
#include <atomic>
#include <thread>
#include <chrono>

#ifdef _WIN32
#define NOMINMAX  // Prevent Windows.h from defining min/max macros
#include <windows.h>
#include <conio.h>
#include "windows/media_foundation/media_foundation_capture.h"
#include "windows/decklink/decklink_capture.h"
#include "capture/DeckLinkDeviceEnumerator.h"
#else
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#ifdef __linux__
#include "linux/v4l2/v4l2_capture.h"
#endif
#endif

#include "common/app_controller.h"
#include "common/version.h"
#include "common/logger.h"

namespace {

// Global variables for signal handling
std::atomic<bool> g_shutdown_requested(false);
std::unique_ptr<ndi_bridge::AppController> g_app_controller;

// Signal handler
void signalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        ndi_bridge::Logger::info("\nShutdown requested...");
        g_shutdown_requested = true;
    }
}

// Print usage information
void printUsage(const char* program_name) {
    std::cout << "Usage: " << program_name << " [device_name] [ndi_name]" << std::endl;
    std::cout << std::endl;
    std::cout << "Ultra-low latency NDI bridge for Intel N100" << std::endl;
    std::cout << "Runs with maximum performance settings always." << std::endl;
    std::cout << std::endl;
    std::cout << "Arguments:" << std::endl;
    std::cout << "  device_name   V4L2 device (default: /dev/video0)" << std::endl;
    std::cout << "  ndi_name      NDI stream name (default: 'Media Bridge')" << std::endl;
    std::cout << std::endl;
    std::cout << "Example:" << std::endl;
    std::cout << "  " << program_name << " /dev/video0 \"HDMI Input\"" << std::endl;
}

} // anonymous namespace

int main(int argc, char* argv[]) {
    // Check for --version BEFORE any initialization (no latency impact)
    if (argc == 2 && std::string(argv[1]) == "--version") {
        std::cout << "Media Bridge v" << NDI_BRIDGE_VERSION << std::endl;
        return 0;
    }
    
    // Log version on startup
    ndi_bridge::Logger::logVersion(NDI_BRIDGE_VERSION);
    ndi_bridge::Logger::info("Ultra-Low Latency Media Bridge starting...");
    
    // Simple argument parsing - NO OPTIONS
    std::string device_name = "/dev/video0";
    std::string ndi_name = "Media Bridge";
    
    if (argc > 1) {
        device_name = argv[1];
    }
    if (argc > 2) {
        ndi_name = argv[2];
    }
    if (argc > 3 || (argc > 1 && std::string(argv[1]) == "--help")) {
        printUsage(argv[0]);
        return 0;
    }
    
    // Log configuration
    ndi_bridge::Logger::info("Device: " + device_name);
    ndi_bridge::Logger::info("NDI Name: " + ndi_name);
    
    // Setup signal handlers
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);
    
    // Create app controller with NO retry (run forever)
    ndi_bridge::AppController::Config config;
    config.device_name = device_name;
    config.ndi_name = ndi_name;
    config.verbose = true;  // Always verbose for monitoring
    config.auto_retry = true;
    config.retry_delay_ms = 1000;  // Fast retry
    config.max_retries = -1;  // Never give up
    
    g_app_controller = std::make_unique<ndi_bridge::AppController>(config);
    
    // Create V4L2 capture - NO CONFIGURATION
    auto v4l2_capture = std::make_unique<ndi_bridge::v4l2::V4L2Capture>();
    g_app_controller->setCaptureDevice(std::move(v4l2_capture));
    
    // Start
    if (!g_app_controller->start()) {
        ndi_bridge::Logger::error("Failed to start");
        return 1;
    }
    
    ndi_bridge::Logger::info("Running with maximum performance...");
    
    // Run until stopped
    while (!g_shutdown_requested && g_app_controller->isRunning()) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    
    // Cleanup
    g_app_controller->stop();
    g_app_controller.reset();
    
    return 0;
}
