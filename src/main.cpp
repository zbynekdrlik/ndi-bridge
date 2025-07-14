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

#ifdef _WIN32
#define NOMINMAX  // Prevent Windows.h from defining min/max macros
#include <windows.h>
#include <conio.h>
#include "windows/media_foundation/media_foundation_capture.h"
#include "capture/DeckLinkCaptureDevice.h"
#include "capture/DeckLinkDeviceEnumerator.h"
#else
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
// Linux capture implementation would go here
#endif

#include "common/app_controller.h"
#include "common/version.h"

namespace {

// Global variables for signal handling
std::atomic<bool> g_shutdown_requested(false);
std::unique_ptr<ndi_bridge::AppController> g_app_controller;

// Capture type enum
enum class CaptureType {
    MediaFoundation,
    DeckLink
};

// Signal handler
void signalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        std::cout << "\nShutdown requested..." << std::endl;
        g_shutdown_requested = true;
        if (g_app_controller) {
            g_app_controller->stop();
        }
    }
}

// Platform-specific console input check
bool isKeyPressed() {
#ifdef _WIN32
    return _kbhit() != 0;
#else
    struct termios oldt, newt;
    int ch;
    int oldf;
    
    tcgetattr(STDIN_FILENO, &oldt);
    newt = oldt;
    newt.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);
    oldf = fcntl(STDIN_FILENO, F_GETFL, 0);
    fcntl(STDIN_FILENO, F_SETFL, oldf | O_NONBLOCK);
    
    ch = getchar();
    
    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    fcntl(STDIN_FILENO, F_SETFL, oldf);
    
    if (ch != EOF) {
        ungetc(ch, stdin);
        return true;
    }
    
    return false;
#endif
}

// Clear any pending input
void clearInput() {
#ifdef _WIN32
    while (_kbhit()) {
        _getch();
    }
#else
    int c;
    while ((c = getchar()) != '\n' && c != EOF);
#endif
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
    std::cout << "Press Enter to stop the application while running." << std::endl;
}

// List available capture devices
void listDevices(CaptureType type = CaptureType::MediaFoundation) {
#ifdef _WIN32
    if (type == CaptureType::MediaFoundation || type == CaptureType::DeckLink) {
        // Initialize COM
        HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(hr)) {
            std::cerr << "Failed to initialize COM" << std::endl;
            return;
        }
    }
    
    if (type == CaptureType::MediaFoundation) {
        auto capture = std::make_unique<ndi_bridge::MediaFoundationCapture>();
        auto devices = capture->enumerateDevices();
        
        std::cout << "\nMedia Foundation Devices:" << std::endl;
        if (devices.empty()) {
            std::cout << "  No Media Foundation devices found." << std::endl;
        } else {
            for (size_t i = 0; i < devices.size(); ++i) {
                const auto& device = devices[i];
                std::cout << "  " << i << ": " << device.name;
                if (!device.id.empty() && device.id != device.name) {
                    std::cout << " (" << device.id << ")";
                }
                std::cout << std::endl;
            }
        }
    } else if (type == CaptureType::DeckLink) {
        DeckLinkDeviceEnumerator enumerator;
        enumerator.EnumerateDevices();
        
        std::cout << "\nDeckLink Devices:" << std::endl;
        auto deviceNames = enumerator.GetDeviceNames();
        if (deviceNames.empty()) {
            std::cout << "  No DeckLink devices found." << std::endl;
        } else {
            for (size_t i = 0; i < deviceNames.size(); ++i) {
                std::cout << "  " << i << ": " << deviceNames[i] << std::endl;
            }
        }
    }
    
    CoUninitialize();
#else
    std::cout << "Device enumeration not yet implemented for Linux." << std::endl;
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
    if (type == CaptureType::MediaFoundation) {
        auto capture = std::make_unique<ndi_bridge::MediaFoundationCapture>();
        auto devices = capture->enumerateDevices();
        
        if (devices.empty()) {
            std::cerr << "No Media Foundation devices found." << std::endl;
            return "";
        }
        
        std::cout << "\nAvailable Media Foundation Devices:" << std::endl;
        for (size_t i = 0; i < devices.size(); ++i) {
            std::cout << i << ": " << devices[i].name << std::endl;
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
    } else if (type == CaptureType::DeckLink) {
        DeckLinkDeviceEnumerator enumerator;
        enumerator.EnumerateDevices();
        
        auto deviceNames = enumerator.GetDeviceNames();
        if (deviceNames.empty()) {
            std::cerr << "No DeckLink devices found." << std::endl;
            return "";
        }
        
        std::cout << "\nAvailable DeckLink Devices:" << std::endl;
        for (size_t i = 0; i < deviceNames.size(); ++i) {
            std::cout << i << ": " << deviceNames[i] << std::endl;
        }
        
        int chosenIndex = -1;
        while (chosenIndex < 0 || chosenIndex >= static_cast<int>(deviceNames.size())) {
            std::cout << "Select device index: ";
            
            if (!(std::cin >> chosenIndex)) {
                std::cin.clear();
                std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
                std::cerr << "Invalid input. Please enter a number." << std::endl;
                chosenIndex = -1;
                continue;
            }
            
            if (chosenIndex < 0 || chosenIndex >= static_cast<int>(deviceNames.size())) {
                std::cerr << "Invalid device index. Please try again." << std::endl;
            }
        }
        
        std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
        
        std::cout << "Using device: " << deviceNames[chosenIndex] << std::endl;
        return deviceNames[chosenIndex];
    }
#else
    std::cerr << "Device selection not yet implemented for Linux." << std::endl;
#endif
    return "";
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
    // Log version on startup (updated to 1.1.0 for DeckLink support)
    std::cout << "[main] NDI Bridge version " << NDI_BRIDGE_VERSION << " starting..." << std::endl;
    
    // Parse command line arguments
    CommandLineArgs args = parseArgs(argc, argv);
    
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
    
    if (args.list_devices) {
        // List both types if not specified
        if (args.capture_type_str.empty()) {
            listDevices(CaptureType::MediaFoundation);
            listDevices(CaptureType::DeckLink);
        } else {
            listDevices(args.capture_type);
        }
        return 0;
    }
    
    // Platform-specific initialization
#ifdef _WIN32
    // Initialize COM for Media Foundation and DeckLink
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr)) {
        std::cerr << "Failed to initialize COM: 0x" << std::hex << hr << std::endl;
        return 1;
    }
    
    // Disable console quick edit mode to prevent accidental pausing
    HANDLE hInput = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode;
    GetConsoleMode(hInput, &mode);
    mode &= ~ENABLE_QUICK_EDIT_MODE;
    SetConsoleMode(hInput, mode);
#endif
    
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
        std::cout << "[Status] " << status << std::endl;
    });
    
    g_app_controller->setErrorCallback([](const std::string& error, bool recoverable) {
        std::cerr << "[Error] " << error;
        if (recoverable) {
            std::cerr << " (recoverable)";
        }
        std::cerr << std::endl;
    });
    
    // Create capture device based on type
#ifdef _WIN32
    std::unique_ptr<ndi_bridge::ICaptureDevice> capture_device;
    
    if (args.capture_type == CaptureType::MediaFoundation) {
        std::cout << "Using Media Foundation capture" << std::endl;
        capture_device = std::make_unique<ndi_bridge::MediaFoundationCapture>();
    } else if (args.capture_type == CaptureType::DeckLink) {
        std::cout << "Using DeckLink capture" << std::endl;
        capture_device = std::make_unique<DeckLinkCaptureDevice>();
    }
#else
    std::cerr << "Linux capture not yet implemented" << std::endl;
    return 1;
#endif
    
    g_app_controller->setCaptureDevice(std::move(capture_device));
    
    // Start the application
    std::cout << "Starting capture pipeline..." << std::endl;
    if (!g_app_controller->start()) {
        std::cerr << "Failed to start application" << std::endl;
        #ifdef _WIN32
        CoUninitialize();
        #endif
        return 1;
    }
    
    std::cout << std::endl;
    std::cout << "NDI Bridge is running. Press Enter to stop..." << std::endl;
    std::cout << std::endl;
    
    // Clear any pending input
    clearInput();
    
    // Main loop - wait for Enter key or shutdown signal
    while (!g_shutdown_requested && g_app_controller->isRunning()) {
        // Check for key press
        if (isKeyPressed()) {
            int ch = std::cin.get();
            if (ch == '\n' || ch == '\r') {
                std::cout << "Enter key pressed, stopping..." << std::endl;
                break;
            }
        }
        
        // Small sleep to prevent busy waiting
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        
        // Print statistics periodically if verbose
        if (args.verbose) {
            static auto last_stats_time = std::chrono::steady_clock::now();
            auto now = std::chrono::steady_clock::now();
            
            if (now - last_stats_time >= std::chrono::seconds(10)) {
                uint64_t captured, sent, dropped;
                g_app_controller->getFrameStats(captured, sent, dropped);
                
                std::cout << "[Stats] Frames - Captured: " << captured 
                         << ", Sent: " << sent 
                         << ", Dropped: " << dropped;
                
                int connections = g_app_controller->getNdiConnectionCount();
                std::cout << ", NDI Connections: " << connections;
                
                std::cout << std::endl;
                
                last_stats_time = now;
            }
        }
    }
    
    // Stop the application
    std::cout << "Stopping application..." << std::endl;
    g_app_controller->stop();
    g_app_controller.reset();
    
    std::cout << "Exiting." << std::endl;
    
    // In command-line mode (positional parameters), wait for user input before closing
    if (args.use_positional) {
        std::cout << "Press Enter to exit." << std::endl;
        clearInput();
        std::cin.get();
    }
    
    // Cleanup
#ifdef _WIN32
    CoUninitialize();
#endif
    
    std::cout << "Application stopped successfully." << std::endl;
    return 0;
}
