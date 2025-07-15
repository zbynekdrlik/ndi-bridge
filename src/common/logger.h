#pragma once

#include <string>
#include <iostream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <mutex>

namespace ndi_bridge {

/**
 * Logger class implementing the LLM instruction format:
 * [script_name] [timestamp] message
 */
class Logger {
public:
    enum class Level {
        INFO,
        WARNING,
        ERROR,
        DEBUG
    };

    /**
     * Initialize the logger with a module name
     * @param module_name The name of the module/script for log messages
     */
    static void initialize(const std::string& module_name);

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
    static std::string module_name_;
    static bool verbose_;
};

} // namespace ndi_bridge
