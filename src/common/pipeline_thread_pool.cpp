#include "pipeline_thread_pool.h"
#include "logger.h"
#include <sstream>

#ifdef __linux__
#include <sched.h>
#include <pthread.h>
#endif

#ifdef _WIN32
#include <windows.h>
#endif

namespace ndi_bridge {

PipelineThreadPool::PipelineThreadPool() {
    Logger::info("PipelineThreadPool: Created, CPU cores available: " + 
                std::to_string(getCpuCoreCount()));
}

PipelineThreadPool::~PipelineThreadPool() {
    stopAll();
    waitAll();
    Logger::info("PipelineThreadPool: Destroyed");
}

size_t PipelineThreadPool::createThread(const std::string& name, ThreadFunc func, int cpu_core) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    size_t thread_id = threads_.size();
    auto info = std::make_unique<ThreadInfo>();
    info->name = name;
    info->cpu_core = cpu_core;
    info->should_stop = false;
    
    // Create thread wrapper that includes monitoring
    auto thread_wrapper = [this, thread_id, func, name]() {
        Logger::info("Thread '" + name + "' started (ID: " + std::to_string(thread_id) + ")");
        
        try {
            func();
        } catch (const std::exception& e) {
            Logger::error("Thread '" + name + "' exception: " + std::string(e.what()));
        } catch (...) {
            Logger::error("Thread '" + name + "' unknown exception");
        }
        
        Logger::info("Thread '" + name + "' stopped");
    };
    
    // Create the thread
    info->thread = std::make_unique<std::thread>(thread_wrapper);
    
    // Set CPU affinity if requested
    if (cpu_core >= 0 && cpu_core < getCpuCoreCount()) {
        if (setThreadAffinity(*info->thread, cpu_core)) {
            Logger::debug("Thread '" + name + "' bound to CPU core " + std::to_string(cpu_core));
        } else {
            Logger::warning("Failed to set CPU affinity for thread '" + name + "'");
        }
    }
    
    // Try to set real-time priority (may require permissions)
    if (!setThreadRealtime(*info->thread)) {
        Logger::debug("Could not set real-time priority for thread '" + name + "' (normal)");
    }
    
    threads_.push_back(std::move(info));
    return thread_id;
}

void PipelineThreadPool::stopThread(size_t thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (thread_id < threads_.size() && threads_[thread_id]) {
        threads_[thread_id]->should_stop = true;
    }
}

void PipelineThreadPool::stopAll() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    for (auto& info : threads_) {
        if (info) {
            info->should_stop = true;
        }
    }
}

void PipelineThreadPool::waitAll() {
    std::vector<std::thread*> threads_to_join;
    
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto& info : threads_) {
            if (info && info->thread && info->thread->joinable()) {
                threads_to_join.push_back(info->thread.get());
            }
        }
    }
    
    // Join threads outside of lock to avoid deadlock
    for (auto* thread : threads_to_join) {
        thread->join();
    }
}

const PipelineThreadPool::ThreadInfo* PipelineThreadPool::getThreadInfo(size_t thread_id) const {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (thread_id < threads_.size()) {
        return threads_[thread_id].get();
    }
    return nullptr;
}

void PipelineThreadPool::updateThreadStats(size_t thread_id, double processing_time_ms) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (thread_id < threads_.size() && threads_[thread_id]) {
        auto& info = *threads_[thread_id];
        info.iterations++;
        
        // Update moving average
        if (info.avg_processing_time_ms == 0.0) {
            info.avg_processing_time_ms = processing_time_ms;
        } else {
            // Exponential moving average with alpha=0.1
            info.avg_processing_time_ms = 0.9 * info.avg_processing_time_ms + 0.1 * processing_time_ms;
        }
    }
}

bool PipelineThreadPool::shouldStop(size_t thread_id) const {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (thread_id < threads_.size() && threads_[thread_id]) {
        return threads_[thread_id]->should_stop.load();
    }
    return true;
}

bool PipelineThreadPool::setThreadAffinity(std::thread& thread, int cpu_core) {
#ifdef __linux__
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_core, &cpuset);
    
    pthread_t native_handle = thread.native_handle();
    int result = pthread_setaffinity_np(native_handle, sizeof(cpu_set_t), &cpuset);
    
    return result == 0;
#elif defined(_WIN32)
    HANDLE native_handle = thread.native_handle();
    DWORD_PTR mask = 1ULL << cpu_core;
    DWORD_PTR result = SetThreadAffinityMask(native_handle, mask);
    
    return result != 0;
#else
    // Not implemented for other platforms
    return false;
#endif
}

bool PipelineThreadPool::setThreadRealtime(std::thread& thread) {
#ifdef __linux__
    struct sched_param param;
    param.sched_priority = 1;  // Lowest real-time priority
    
    pthread_t native_handle = thread.native_handle();
    int result = pthread_setschedparam(native_handle, SCHED_FIFO, &param);
    
    return result == 0;
#elif defined(_WIN32)
    HANDLE native_handle = thread.native_handle();
    BOOL result = SetThreadPriority(native_handle, THREAD_PRIORITY_TIME_CRITICAL);
    
    return result != 0;
#else
    // Not implemented for other platforms
    return false;
#endif
}

int PipelineThreadPool::getCpuCoreCount() {
    return std::thread::hardware_concurrency();
}

} // namespace ndi_bridge
