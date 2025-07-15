// DeckLinkStatistics.h
#pragma once

#include <atomic>
#include <chrono>
#include <deque>
#include <mutex>
#include "../ICaptureDevice.h"  // For CaptureStatistics

/**
 * @brief Statistics tracking for DeckLink capture
 * 
 * Handles frame counting, FPS calculation using rolling averages,
 * and periodic statistics logging.
 */
class DeckLinkStatistics {
public:
    DeckLinkStatistics();
    ~DeckLinkStatistics() = default;
    
    /**
     * @brief Reset all statistics counters
     */
    void Reset();
    
    /**
     * @brief Record a captured frame
     */
    void RecordFrame();
    
    /**
     * @brief Record a dropped frame
     */
    void RecordDroppedFrame();
    
    /**
     * @brief Get current statistics
     * @param stats Output statistics structure
     * @param captureStartTime When capture started
     */
    void GetStatistics(CaptureStatistics& stats, 
                      const std::chrono::high_resolution_clock::time_point& captureStartTime) const;
    
    /**
     * @brief Calculate rolling average FPS over last 5 seconds
     * @return Current FPS or 0.0 if insufficient data
     */
    double CalculateRollingFPS() const;
    
    /**
     * @brief Log current statistics to console
     * @param frameTimescale Frame timescale for expected FPS
     * @param frameDuration Frame duration for expected FPS
     */
    void LogStatistics(int64_t frameTimescale, int64_t frameDuration);
    
    /**
     * @brief Check if statistics should be logged (every 60 frames)
     * @return true if logging is due
     */
    bool ShouldLogStatistics() const;
    
    /**
     * @brief Get total captured frames
     * @return Frame count
     */
    uint64_t GetFrameCount() const { return m_frameCount; }
    
    /**
     * @brief Get total dropped frames
     * @return Dropped frame count
     */
    uint64_t GetDroppedFrames() const { return m_droppedFrames; }
    
private:
    /**
     * @brief Frame timestamp record for FPS calculation
     */
    struct FrameTimestamp {
        int frameNumber;
        std::chrono::high_resolution_clock::time_point timestamp;
    };
    
    // Statistics counters
    std::atomic<uint64_t> m_frameCount;
    std::atomic<uint64_t> m_droppedFrames;
    
    // Frame history for rolling average
    mutable std::mutex m_historyMutex;
    std::deque<FrameTimestamp> m_frameHistory;
    
    // Constants
    static constexpr int LOG_INTERVAL_FRAMES = 60;
    static constexpr int ROLLING_AVERAGE_SECONDS = 5;
    static constexpr int HISTORY_RETENTION_SECONDS = 60;
};
