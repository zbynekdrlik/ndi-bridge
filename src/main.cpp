#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <csignal>
#include <cstring>
#include <atomic>
#include <thread>
#include <chrono>
#include <limits>
#include <iomanip>  // For std::fixed and std::setprecision

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
// Linux capture implementation would go here
#endif

#include "common/app_controller.h"
#include "common/version.h"
#include "common/logger.h"

namespace {

// Global variables for signal handling
std::atomic<bool> g_shutdown_requested(false);
std::unique_ptr<ndi_bridge::AppController> g_app_controller;

// Global capture device reference for NZXT workaround
std::unique_ptr<ndi_bridge::ICaptureDevice> g_capture_device;

// Capture type enum
enum class CaptureType {
    MediaFoundation,
    DeckLink
};

// Signal handler
void signalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        ndi_bridge::Logger::info("\nShutdown requested...");
        g_shutdown_requested = true;
        // Don't stop here - let main handle the graceful shutdown
    }
}

// Print usage information
void printUsage(const char* program_name) {
    std::cout << "Usage: " << program_name << " [options]" << std::endl;
    std::cout << "       " << program_name << " <device_name> <ndi_name>" << std::endl;
    std::cout << std::endl;
    std::cout << "Options:" << std::endl;
    std::cout << "  -t, --type <type>       Capture type: mf (Media Foundation) or dl (DeckLink)" << std::endl;
    std::cout << "  -d, --device <n>        Capture device name (default: interactive selection)" << std::endl;
    std::cout << "  -n, --ndi-name <n>      NDI sender name (default: 'NDI Bridge')" << std::endl;
    std::cout << "  -l, --list-devices      List available capture devices and exit" << std::endl;
    std::cout << "  -v, --verbose           Enable verbose logging" << std::endl;
    std::cout << "  --no-retry              Disable automatic retry on errors" << std::endl;
    std::cout << "  --retry-delay <ms>      Delay between retries (default: 5000)" << std::endl;
    std::cout << "  --max-retries <count>   Maximum retry attempts (-1 for infinite, default: -1)" << std::endl;
    std::cout << "  -h, --help              Show this help message" << std::endl;
    std::cout << "  --version               Show version information" << std::endl;
    std::cout << std::endl;
    std::cout << "Press Ctrl+C to stop the application while running." << std::endl;
}

// List available capture devices
void listDevices(CaptureType type = CaptureType::MediaFoundation) {
#ifdef _WIN32
    if (type == CaptureType::MediaFoundation) {
        auto capture = std::make_unique<ndi_bridge::MediaFoundationCapture>();
        auto devices = capture->enumerateDevices();
        
        ndi_bridge::Logger::info("\nMedia Foundation Devices:");
        if (devices.empty()) {
            ndi_bridge::Logger::info("  No Media Foundation devices found.");
        } else {
            for (size_t i = 0; i < devices.size(); ++i) {
                const auto& device = devices[i];
                std::stringstream ss;
                ss << "  " << i << ": " << device.name;
                if (!device.id.empty() && device.id != device.name) {
                    ss << " (" << device.id << ")";
                }
                ndi_bridge::Logger::info(ss.str());
            }
        }
    } else if (type == CaptureType::DeckLink) {
        auto capture = std::make_unique<ndi_bridge::DeckLinkCapture>();
        auto devices = capture->enumerateDevices();
        
        ndi_bridge::Logger::info("\nDeckLink Devices:");
        if (devices.empty()) {
            ndi_bridge::Logger::info("  No DeckLink devices found.");
        } else {
            for (size_t i = 0; i < devices.size(); ++i) {
                const auto& device = devices[i];
                std::stringstream ss;
                ss << "  " << i << ": " << device.name;
                if (!device.id.empty() && device.id != device.name) {
                    ss << " (" << device.id << ")";
                }
                ndi_bridge::Logger::info(ss.str());
            }
        }
    }
#else
    ndi_bridge::Logger::info("Device enumeration not yet implemented for Linux.");
#endif
}

// Select capture type interactively
CaptureType selectCaptureTypeInteractive() {
    std::cout << "\nSelect capture type:" << std::endl;
    std::cout << "0: Media Foundation (Webcams, USB capture)" << std::endl;
    std::cout << "1: DeckLink (Blackmagic devices)" << std::endl;
    
    int choice = -1;
    while (choice < 0 || choice > 1) {
        std::cout << "Select type (0-1): ";
        
        if (!(std::cin >> choice)) {
            std::cin.clear();
            std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
            std::cerr << "Invalid input. Please enter a number." << std::endl;
            choice = -1;
            continue;
        }
        
        if (choice < 0 || choice > 1) {
            std::cerr << "Invalid choice. Please try again." << std::endl;
        }
    }
    
    std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
    
    return (choice == 0) ? CaptureType::MediaFoundation : CaptureType::DeckLink;
}

// Select device interactively
std::string selectDeviceInteractive(CaptureType type) {
#ifdef _WIN32
    std::unique_ptr<ndi_bridge::ICaptureDevice> capture;
    
    if (type == CaptureType::MediaFoundation) {
        capture = std::make_unique<ndi_bridge::MediaFoundationCapture>();
    } else if (type == CaptureType::DeckLink) {
        capture = std::make_unique<ndi_bridge::DeckLinkCapture>();
    }
    
    auto devices = capture->enumerateDevices();
    
    if (devices.empty()) {
        std::cerr << "No devices found." << std::endl;
        return "";
    }
    
    ndi_bridge::Logger::info("\nAvailable Devices:");
    for (size_t i = 0; i < devices.size(); ++i) {
        ndi_bridge::Logger::info(std::to_string(i) + ": " + devices[i].name);
    }
    
    int chosenIndex = -1;
    while (chosenIndex < 0 || chosenIndex >= static_cast<int>(devices.size())) {
        std::cout << "Select device index: ";
        
        if (!(std::cin >> chosenIndex)) {
            std::cin.clear();
            std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
            std::cerr << "Invalid input. Please enter a number." << std::endl;
            chosenIndex = -1;
            continue;
        }
        
        if (chosenIndex < 0 || chosenIndex >= static_cast<int>(devices.size())) {
            std::cerr << "Invalid device index. Please try again." << std::endl;
        }
    }
    
    std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
    
    std::cout << "Using device: " << devices[chosenIndex].name << std::endl;
    return devices[chosenIndex].name;
#else
    std::cerr << "Device selection not yet implemented for Linux." << std::endl;
    return "";
#endif
}

// Parse command line arguments
struct CommandLineArgs {
    std::string device_name;
    std::string ndi_name = "NDI Bridge";
    std::string capture_type_str;
    CaptureType capture_type = CaptureType::MediaFoundation;
    bool list_devices = false;
    bool verbose = false;
    bool show_help = false;
    bool show_version = false;
    bool auto_retry = true;
    int retry_delay_ms = 5000;
    int max_retries = -1;
    bool use_positional = false;
    bool use_interactive = false;
};

CommandLineArgs parseArgs(int argc, char* argv[]) {
    CommandLineArgs args;
    
    // Check for positional parameters (compatibility with original)
    if (argc == 3 && argv[1][0] != '-' && argv[2][0] != '-') {
        args.device_name = argv[1];
        args.ndi_name = argv[2];
        args.use_positional = true;
        // Default to Media Foundation for backward compatibility
        args.capture_type = CaptureType::MediaFoundation;
        std::cout << "Command-line mode: device name = \"" << args.device_name
                  << "\", NDI stream name = \"" << args.ndi_name << "\"" << std::endl;
        return args;
    }
    
    // Parse option flags
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        
        if (arg == "-t" || arg == "--type") {
            if (i + 1 < argc) {
                args.capture_type_str = argv[++i];
                if (args.capture_type_str == "mf" || args.capture_type_str == "mediafoundation") {
                    args.capture_type = CaptureType::MediaFoundation;
                } else if (args.capture_type_str == "dl" || args.capture_type_str == "decklink") {
                    args.capture_type = CaptureType::DeckLink;
                } else {
                    std::cerr << "Error: Invalid capture type. Use 'mf' or 'dl'" << std::endl;
                    args.show_help = true;
                }
            } else {
                std::cerr << "Error: --type requires an argument" << std::endl;
                args.show_help = true;
            }
        } else if (arg == "-d" || arg == "--device") {
            if (i + 1 < argc) {
                args.device_name = argv[++i];
            } else {
                std::cerr << "Error: --device requires an argument" << std::endl;
                args.show_help = true;
            }
        } else if (arg == "-n" || arg == "--ndi-name") {
            if (i + 1 < argc) {
                args.ndi_name = argv[++i];
            } else {
                std::cerr << "Error: --ndi-name requires an argument" << std::endl;
                args.show_help = true;
            }
        } else if (arg == "-l" || arg == "--list-devices") {
            args.list_devices = true;
        } else if (arg == "-v" || arg == "--verbose") {
            args.verbose = true;
        } else if (arg == "--no-retry") {
            args.auto_retry = false;
        } else if (arg == "--retry-delay") {
            if (i + 1 < argc) {
                args.retry_delay_ms = std::stoi(argv[++i]);
            } else {
                std::cerr << "Error: --retry-delay requires an argument" << std::endl;
                args.show_help = true;
            }
        } else if (arg == "--max-retries") {
            if (i + 1 < argc) {
                args.max_retries = std::stoi(argv[++i]);
            } else {
                std::cerr << "Error: --max-retries requires an argument" << std::endl;
                args.show_help = true;
            }
        } else if (arg == "-h" || arg == "--help") {
            args.show_help = true;
        } else if (arg == "--version") {
            args.show_version = true;
        } else {
            std::cerr << "Error: Unknown argument: " << arg << std::endl;
            args.show_help = true;
        }
    }
    
    // If no device specified and not showing help/version/list, use interactive mode
    if (args.device_name.empty() && !args.show_help && !args.show_version && !args.list_devices) {
        args.use_interactive = true;
    }
    
    return args;
}

} // anonymous namespace

int main(int argc, char* argv[]) {
    // Log version on startup - only place where version should be logged
    ndi_bridge::Logger::logVersion(NDI_BRIDGE_VERSION);
    ndi_bridge::Logger::info("NDI Bridge starting...");
    
    // Parse command line arguments
    CommandLineArgs args = parseArgs(argc, argv);
    
    // Set verbose mode if requested
    if (args.verbose) {
        ndi_bridge::Logger::setVerbose(true);
    }
    
    if (args.show_help) {
        printUsage(argv[0]);
        return 0;
    }
    
    if (args.show_version) {
        std::cout << "NDI Bridge version " << NDI_BRIDGE_VERSION << std::endl;
        std::cout << "Build type: " << NDI_BRIDGE_BUILD_TYPE << std::endl;
        std::cout << "Platform: " << NDI_BRIDGE_PLATFORM << std::endl;
        std::cout << "Build date: " << __DATE__ << " " << __TIME__ << std::endl;
        return 0;
    }
    
    // Platform-specific initialization
#ifdef _WIN32
    // Initialize COM for Media Foundation and DeckLink
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr)) {
        std::stringstream ss;
        ss << "Failed to initialize COM: 0x" << std::hex << hr;
        ndi_bridge::Logger::error(ss.str());
        return 1;
    }
    
    // Disable console quick edit mode to prevent accidental pausing
    HANDLE hInput = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode;
    GetConsoleMode(hInput, &mode);
    mode &= ~ENABLE_QUICK_EDIT_MODE;
    SetConsoleMode(hInput, mode);
#endif
    
    if (args.list_devices) {
        // List both types if not specified
        if (args.capture_type_str.empty()) {
            listDevices(CaptureType::MediaFoundation);
            listDevices(CaptureType::DeckLink);
        } else {
            listDevices(args.capture_type);
        }
        #ifdef _WIN32
        CoUninitialize();
        #endif
        return 0;
    }
    
    // Interactive capture type and device selection if needed
    if (args.use_interactive) {
        // If type not specified, ask for it
        if (args.capture_type_str.empty()) {
            args.capture_type = selectCaptureTypeInteractive();
        }
        
        args.device_name = selectDeviceInteractive(args.capture_type);
        if (args.device_name.empty()) {
            #ifdef _WIN32
            CoUninitialize();
            #endif
            return 1;
        }
        
        std::cout << "Enter NDI stream name: ";
        std::getline(std::cin, args.ndi_name);
        if (args.ndi_name.empty()) {
            args.ndi_name = "NDI Bridge";
        }
    }
    
    // Set up signal handlers
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);
    
    // Create application controller
    ndi_bridge::AppController::Config config;
    config.device_name = args.device_name;
    config.ndi_name = args.ndi_name;
    config.verbose = args.verbose;
    config.auto_retry = args.auto_retry;
    config.retry_delay_ms = args.retry_delay_ms;
    config.max_retries = args.max_retries;
    
    g_app_controller = std::make_unique<ndi_bridge::AppController>(config);
    
    // Set up callbacks
    g_app_controller->setStatusCallback([](const std::string& status) {
        ndi_bridge::Logger::info("[Status] " + status);
    });
    
    g_app_controller->setErrorCallback([](const std::string& error, bool recoverable) {
        std::stringstream ss;
        ss << "[Error] " << error;
        if (recoverable) {
            ss << " (recoverable)";
        }
        ndi_bridge::Logger::error(ss.str());
    });
    
    // Create capture device based on type
#ifdef _WIN32
    // Keep capture device in global for NZXT workaround
    bool is_nzxt_device = false;
    
    if (args.capture_type == CaptureType::MediaFoundation) {
        ndi_bridge::Logger::info("Using Media Foundation capture");
        g_capture_device = std::make_unique<ndi_bridge::MediaFoundationCapture>();
        
        // Check if it's NZXT device
        if (args.device_name.find("NZXT") != std::string::npos) {
            is_nzxt_device = true;
            ndi_bridge::Logger::info("NZXT device detected - using special cleanup handling");
        }
    } else if (args.capture_type == CaptureType::DeckLink) {
        ndi_bridge::Logger::info("Using DeckLink capture");
        g_capture_device = std::make_unique<ndi_bridge::DeckLinkCapture>();
    }
    
    // Give ownership to app controller but keep global reference for NZXT
    g_app_controller->setCaptureDevice(std::move(g_capture_device));
#else
    ndi_bridge::Logger::error("Linux capture not yet implemented");
    return 1;
#endif
    
    // Start the application
    ndi_bridge::Logger::info("Starting capture pipeline...");
    if (!g_app_controller->start()) {
        ndi_bridge::Logger::error("Failed to start application");
        #ifdef _WIN32
        CoUninitialize();
        #endif
        return 1;
    }
    
    ndi_bridge::Logger::info("");
    ndi_bridge::Logger::info("NDI Bridge is running. Press Ctrl+C to stop...");
    ndi_bridge::Logger::info("");
    
    // Main loop - wait for shutdown signal only
    while (!g_shutdown_requested && g_app_controller->isRunning()) {
        // Small sleep to prevent busy waiting
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        
        // Print statistics periodically if verbose
        if (args.verbose) {
            static auto last_stats_time = std::chrono::steady_clock::now();
            auto now = std::chrono::steady_clock::now();
            
            if (now - last_stats_time >= std::chrono::seconds(10)) {
                uint64_t captured, sent, dropped;
                g_app_controller->getFrameStats(captured, sent, dropped);
                
                std::stringstream ss;
                ss << "[Stats] Frames - Captured: " << captured 
                   << ", Sent: " << sent 
                   << ", Dropped: " << dropped;
                
                int connections = g_app_controller->getNdiConnectionCount();
                ss << ", NDI Connections: " << connections;
                
                ndi_bridge::Logger::debug(ss.str());
                
                last_stats_time = now;
            }
        }
    }
    
    // Display final statistics when shutting down
    uint64_t captured, sent, dropped;
    g_app_controller->getFrameStats(captured, sent, dropped);
    
    ndi_bridge::Logger::info("\nFinal Statistics:");
    ndi_bridge::Logger::info("  Frames Captured: " + std::to_string(captured));
    ndi_bridge::Logger::info("  Frames Sent: " + std::to_string(sent));
    
    std::stringstream ss;
    ss << "  Frames Dropped: " << dropped;
    if (captured > 0) {
        double drop_rate = (dropped * 100.0) / captured;
        ss << " (" << std::fixed << std::setprecision(2) << drop_rate << "%)";
    }
    ndi_bridge::Logger::info(ss.str());
    
    int connections = g_app_controller->getNdiConnectionCount();
    ndi_bridge::Logger::info("  NDI Connections: " + std::to_string(connections));
    
    // Stop the application gracefully
    ndi_bridge::Logger::info("Stopping application...");
    g_app_controller->stop();
    
#ifdef _WIN32
    // NZXT workaround: Add delay before cleanup
    if (is_nzxt_device) {
        ndi_bridge::Logger::info("Waiting before cleanup for NZXT device...");
        std::this_thread::sleep_for(std::chrono::milliseconds(1000));
    }
#endif
    
    g_app_controller.reset();
    
    ndi_bridge::Logger::info("Exiting.");
    
    // Cleanup
#ifdef _WIN32
    // NZXT workaround: Add another delay before CoUninitialize
    if (is_nzxt_device) {
        ndi_bridge::Logger::info("Final cleanup delay for NZXT device...");
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    
    CoUninitialize();
#endif
    
    ndi_bridge::Logger::info("Application stopped successfully.");
    return 0;
}
