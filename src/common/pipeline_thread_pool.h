#pragma once

#include <thread>
#include <memory>
#include <functional>
#include <atomic>
#include <string>
#include <vector>
#include <mutex>
#include <chrono>

namespace ndi_bridge {

/**
 * @brief Thread pool for multi-threaded video pipeline
 * 
 * Manages threads with CPU affinity for optimal performance
 * on Intel N100 and similar multi-core processors.
 * 
 * Version: 1.5.0 - Initial implementation
 */
class PipelineThreadPool {
public:
    /**
     * @brief Thread function type
     */
    using ThreadFunc = std::function<void()>;
    
    /**
     * @brief Thread info structure
     */
    struct ThreadInfo {
        std::string name;
        std::unique_ptr<std::thread> thread;
        std::atomic<bool> should_stop{false};
        int cpu_core = -1;  // -1 means no affinity
        uint64_t iterations = 0;
        double avg_processing_time_ms = 0.0;
    };
    
    /**
     * @brief Constructor
     */
    PipelineThreadPool();
    
    /**
     * @brief Destructor - ensures all threads are stopped
     */
    ~PipelineThreadPool();
    
    /**
     * @brief Create and start a thread
     * @param name Thread name for logging
     * @param func Thread function to run
     * @param cpu_core Optional CPU core to bind to (-1 for no affinity)
     * @return Thread ID
     */
    size_t createThread(const std::string& name, ThreadFunc func, int cpu_core = -1);
    
    /**
     * @brief Stop a specific thread
     * @param thread_id Thread ID returned by createThread
     */
    void stopThread(size_t thread_id);
    
    /**
     * @brief Stop all threads
     */
    void stopAll();
    
    /**
     * @brief Wait for all threads to finish
     */
    void waitAll();
    
    /**
     * @brief Get thread info
     * @param thread_id Thread ID
     * @return Thread info or nullptr if not found
     */
    const ThreadInfo* getThreadInfo(size_t thread_id) const;
    
    /**
     * @brief Update thread statistics
     * @param thread_id Thread ID
     * @param processing_time_ms Processing time for this iteration
     */
    void updateThreadStats(size_t thread_id, double processing_time_ms);
    
    /**
     * @brief Get number of active threads
     */
    size_t getThreadCount() const { return threads_.size(); }
    
    /**
     * @brief Check if a thread should stop
     * @param thread_id Thread ID
     * @return true if thread should stop
     */
    bool shouldStop(size_t thread_id) const;
    
    /**
     * @brief Set thread CPU affinity
     * @param thread Native thread handle
     * @param cpu_core CPU core number
     * @return true if successful
     */
    static bool setThreadAffinity(std::thread& thread, int cpu_core);
    
    /**
     * @brief Set thread priority to real-time
     * @param thread Native thread handle
     * @return true if successful
     */
    static bool setThreadRealtime(std::thread& thread);
    
    /**
     * @brief Get number of CPU cores
     */
    static int getCpuCoreCount();
    
private:
    // Disable copy
    PipelineThreadPool(const PipelineThreadPool&) = delete;
    PipelineThreadPool& operator=(const PipelineThreadPool&) = delete;
    
    std::vector<std::unique_ptr<ThreadInfo>> threads_;
    mutable std::mutex mutex_;
};

/**
 * @brief Helper class for thread performance monitoring
 */
class ThreadTimer {
public:
    ThreadTimer(PipelineThreadPool& pool, size_t thread_id)
        : pool_(pool), thread_id_(thread_id) {
        start_ = std::chrono::high_resolution_clock::now();
    }
    
    ~ThreadTimer() {
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration<double, std::milli>(end - start_).count();
        pool_.updateThreadStats(thread_id_, duration);
    }
    
private:
    PipelineThreadPool& pool_;
    size_t thread_id_;
    std::chrono::high_resolution_clock::time_point start_;
};

} // namespace ndi_bridge
