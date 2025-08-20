#include "logger.h"

namespace ndi_bridge {

// Static member initialization
std::mutex Logger::mutex_;
bool Logger::verbose_ = false;

void Logger::info(const std::string& message) {
    log(Level::LVL_INFO, message);
}

void Logger::warning(const std::string& message) {
    log(Level::LVL_WARNING, message);
}

void Logger::error(const std::string& message) {
    log(Level::LVL_ERROR, message);
}

void Logger::debug(const std::string& message) {
    if (verbose_) {
        log(Level::LVL_DEBUG, message);
    }
}

void Logger::setVerbose(bool verbose) {
    std::lock_guard<std::mutex> lock(mutex_);
    verbose_ = verbose;
}

void Logger::logVersion(const std::string& version) {
    std::stringstream msg;
    msg << "Version " << version << " loaded";
    info(msg.str());
}

void Logger::metrics(double fps, uint64_t frames, uint64_t dropped, double latency_ms) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Format: [timestamp] METRICS|FPS:xx.xx|FRAMES:xxxxx|DROPPED:x|LATENCY:x.x
    std::cout << "[" << getCurrentTimestamp() << "] METRICS|"
              << "FPS:" << std::fixed << std::setprecision(2) << fps << "|"
              << "FRAMES:" << frames << "|"
              << "DROPPED:" << dropped;
    
    if (latency_ms >= 0) {
        std::cout << "|LATENCY:" << std::fixed << std::setprecision(1) << latency_ms;
    }
    
    std::cout << std::endl;
}

void Logger::log(Level level, const std::string& message) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Get appropriate output stream
    std::ostream* output = &std::cout;
    if (level == Level::LVL_ERROR) {
        output = &std::cerr;
    }
    
    // Format: [timestamp] message
    *output << "[" << getCurrentTimestamp() << "] ";
    
    // Add level prefix for non-info messages
    switch (level) {
        case Level::LVL_WARNING:
            *output << "WARNING: ";
            break;
        case Level::LVL_ERROR:
            *output << "ERROR: ";
            break;
        case Level::LVL_DEBUG:
            *output << "DEBUG: ";
            break;
        case Level::LVL_INFO:
        default:
            // No prefix for info
            break;
    }
    
    *output << message << std::endl;
}

std::string Logger::getCurrentTimestamp() {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    
    std::stringstream ss;
    
#ifdef _WIN32
    // Use localtime_s on Windows for thread safety
    struct tm timeinfo;
    localtime_s(&timeinfo, &time_t);
    ss << std::put_time(&timeinfo, "%Y-%m-%d %H:%M:%S");
#else
    // Use localtime on other platforms
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
#endif
    
    // Add milliseconds
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()
    ) % 1000;
    
    ss << "." << std::setfill('0') << std::setw(3) << ms.count();
    
    return ss.str();
}

} // namespace ndi_bridge
