// Test version that accepts resolution as parameter
#include <iostream>
#include <string>
#include <sstream>
#include "v4l2/v4l2_capture.h"
#include "../common/logger.h"
#include "../common/version.h"

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <device> <resolution>" << std::endl;
        std::cerr << "Example: " << argv[0] << " /dev/video0 1280x720" << std::endl;
        return 1;
    }
    
    std::string device = argv[1];
    std::string resolution = argv[2];
    
    // Parse resolution
    int width, height;
    char x;
    std::stringstream ss(resolution);
    if (!(ss >> width >> x >> height) || x != 'x') {
        std::cerr << "Invalid resolution format. Use WIDTHxHEIGHT (e.g., 1280x720)" << std::endl;
        return 1;
    }
    
    ndi_bridge::Logger::info("Testing resolution: " + std::to_string(width) + "x" + std::to_string(height));
    
    // This is just a placeholder - the actual implementation would need to
    // modify V4L2Capture to accept resolution parameters
    ndi_bridge::Logger::info("Resolution testing not yet implemented in main code");
    ndi_bridge::Logger::info("Please use v4l-ctl to test different resolutions:");
    ndi_bridge::Logger::info("  v4l2-ctl -d " + device + " --set-fmt-video=width=" + 
                            std::to_string(width) + ",height=" + std::to_string(height) + 
                            ",pixelformat=YUYV");
    
    return 0;
}
