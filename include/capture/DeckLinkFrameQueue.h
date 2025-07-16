// DeckLinkFrameQueue.h
#pragma once

#include <deque>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <vector>
#include <atomic>
#include "DeckLinkAPI.h"

/**
 * @brief Thread-safe queue for managing captured DeckLink frames
 * 
 * Handles frame queuing, dropping old frames when full,
 * and thread-safe access to queued frames.
 * 
 * v1.6.0: Reduced queue size from 3 to 1 for minimal latency
 */
class DeckLinkFrameQueue {
public:
    // Maximum number of frames to queue - reduced to 1 for minimal latency (v1.6.0)
    static constexpr size_t MAX_QUEUE_SIZE = 1;
    
    /**
     * @brief Queued frame data structure
     */
    struct QueuedFrame {
        std::vector<uint8_t> data;
        int width = 0;
        int height = 0;
        BMDPixelFormat pixelFormat = bmdFormat8BitYUV;
        std::chrono::steady_clock::time_point timestamp;
    };
    
    DeckLinkFrameQueue();
    ~DeckLinkFrameQueue();
    
    /**
     * @brief Add a frame to the queue
     * @param frameData Raw frame data
     * @param frameSize Size of frame data in bytes
     * @param width Frame width
     * @param height Frame height
     * @param pixelFormat DeckLink pixel format
     * @param droppedFrames Counter to increment if frame is dropped
     */
    void AddFrame(const void* frameData, size_t frameSize, 
                  int width, int height, 
                  BMDPixelFormat pixelFormat,
                  std::atomic<uint64_t>& droppedFrames);
    
    /**
     * @brief Get the next frame from the queue
     * @param frame Output frame data
     * @param timeout Timeout in milliseconds
     * @return true if frame was retrieved, false on timeout or empty queue
     */
    bool GetNextFrame(QueuedFrame& frame, int timeoutMs = 100);
    
    /**
     * @brief Clear all frames from the queue
     */
    void Clear();
    
    /**
     * @brief Check if queue is empty
     * @return true if empty
     */
    bool IsEmpty() const;
    
    /**
     * @brief Get current queue size
     * @return Number of frames in queue
     */
    size_t GetSize() const;
    
    /**
     * @brief Signal that capture is stopping
     */
    void StopCapture();
    
private:
    mutable std::mutex m_mutex;
    std::condition_variable m_frameAvailable;
    std::deque<QueuedFrame> m_queue;
    std::atomic<bool> m_isCapturing;
};
