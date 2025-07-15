#pragma once

#include <string>
#include <iostream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <mutex>

namespace ndi_bridge {

/**
 * Logger class implementing simplified format:
 * [timestamp] message
 * 
 * Module names removed per thread progress decision - not useful in compiled exe
 */
class Logger {
public:
    enum class Level {
        LVL_INFO,
        LVL_WARNING,
        LVL_ERROR,
        LVL_DEBUG
    };

    /**
     * Log a message at INFO level
     */
    static void info(const std::string& message);

    /**
     * Log a message at WARNING level
     */
    static void warning(const std::string& message);

    /**
     * Log a message at ERROR level
     */
    static void error(const std::string& message);

    /**
     * Log a message at DEBUG level (only shown if verbose mode is enabled)
     */
    static void debug(const std::string& message);

    /**
     * Enable or disable verbose logging (debug messages)
     */
    static void setVerbose(bool verbose);

    /**
     * Log version information on startup
     * @param version Version string to log
     */
    static void logVersion(const std::string& version);

private:
    static void log(Level level, const std::string& message);
    static std::string getCurrentTimestamp();
    
    static std::mutex mutex_;
    static bool verbose_;
};

} // namespace ndi_bridge
