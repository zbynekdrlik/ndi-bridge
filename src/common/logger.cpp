#include "logger.h"

namespace ndi_bridge {

// Static member initialization
std::mutex Logger::mutex_;
std::string Logger::module_name_ = "ndi-bridge";
bool Logger::verbose_ = false;

void Logger::initialize(const std::string& module_name) {
    std::lock_guard<std::mutex> lock(mutex_);
    module_name_ = module_name;
}

void Logger::info(const std::string& message) {
    log(Level::INFO, message);
}

void Logger::warning(const std::string& message) {
    log(Level::WARNING, message);
}

void Logger::error(const std::string& message) {
    log(Level::ERROR, message);
}

void Logger::debug(const std::string& message) {
    if (verbose_) {
        log(Level::DEBUG, message);
    }
}

void Logger::setVerbose(bool verbose) {
    std::lock_guard<std::mutex> lock(mutex_);
    verbose_ = verbose;
}

void Logger::logVersion(const std::string& version) {
    std::stringstream msg;
    msg << "Script version " << version << " loaded";
    info(msg.str());
}

void Logger::log(Level level, const std::string& message) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Get appropriate output stream
    std::ostream* output = &std::cout;
    if (level == Level::ERROR) {
        output = &std::cerr;
    }
    
    // Format: [module_name] [timestamp] message
    *output << "[" << module_name_ << "] "
            << "[" << getCurrentTimestamp() << "] ";
    
    // Add level prefix for non-info messages
    switch (level) {
        case Level::WARNING:
            *output << "WARNING: ";
            break;
        case Level::ERROR:
            *output << "ERROR: ";
            break;
        case Level::DEBUG:
            *output << "DEBUG: ";
            break;
        case Level::INFO:
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
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    
    // Add milliseconds
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()
    ) % 1000;
    
    ss << "." << std::setfill('0') << std::setw(3) << ms.count();
    
    return ss.str();
}

} // namespace ndi_bridge
