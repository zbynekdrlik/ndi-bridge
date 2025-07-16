#pragma once

#include <atomic>
#include <memory>
#include <cstdint>
#include <cstring>
#include <immintrin.h>
#include "../capture_interface.h"

namespace ndi_bridge {

/**
 * @brief Lock-free frame queue for multi-threaded pipeline
 * 
 * Uses a ring buffer with atomic operations for thread-safe
 * frame passing between threads without mutexes.
 * 
 * Version: 1.5.0 - Initial implementation for multi-threaded pipeline
 */
class FrameQueue {
public:
    /**
     * @brief Frame data structure for queue
     */
    struct Frame {
        void* data = nullptr;
        size_t size = 0;
        int64_t timestamp_ns = 0;
        ICaptureDevice::VideoFormat format;
        uint32_t buffer_index = 0;  // V4L2 buffer index for requeue
        bool needs_conversion = false;
        
        Frame() = default;
        
        Frame(void* d, size_t s, int64_t t, const ICaptureDevice::VideoFormat& f, 
              uint32_t idx = 0, bool convert = false)
            : data(d), size(s), timestamp_ns(t), format(f), 
              buffer_index(idx), needs_conversion(convert) {}
    };
    
    /**
     * @brief Construct frame queue with specified capacity
     * @param capacity Maximum number of frames in queue
     * @param frame_size Maximum size of each frame in bytes
     */
    explicit FrameQueue(size_t capacity, size_t frame_size);
    
    ~FrameQueue();
    
    /**
     * @brief Try to push a frame to the queue
     * @param frame Frame to push
     * @return true if successful, false if queue is full
     * 
     * Note: This copies the frame data to internal buffer
     */
    bool tryPush(const Frame& frame);
    
    /**
     * @brief Try to pop a frame from the queue
     * @param frame Output frame
     * @return true if successful, false if queue is empty
     * 
     * Note: The frame data pointer points to internal buffer
     */
    bool tryPop(Frame& frame);
    
    /**
     * @brief Check if queue is empty
     */
    bool empty() const;
    
    /**
     * @brief Check if queue is full
     */
    bool full() const;
    
    /**
     * @brief Get current size
     */
    size_t size() const;
    
    /**
     * @brief Get capacity
     */
    size_t capacity() const { return capacity_; }
    
    /**
     * @brief Get dropped frame count (push failures)
     */
    uint64_t getDroppedFrames() const { return dropped_frames_.load(); }
    
private:
    // Disable copy
    FrameQueue(const FrameQueue&) = delete;
    FrameQueue& operator=(const FrameQueue&) = delete;
    
    // Ring buffer for frames
    std::unique_ptr<Frame[]> frames_;
    
    // Pre-allocated memory pool for frame data
    std::unique_ptr<uint8_t[]> data_pool_;
    size_t frame_size_;
    size_t capacity_;
    
    // Atomic indices for lock-free operation
    alignas(64) std::atomic<size_t> head_{0};  // Consumer index
    alignas(64) std::atomic<size_t> tail_{0};  // Producer index
    
    // Statistics
    std::atomic<uint64_t> dropped_frames_{0};
    
    /**
     * @brief Get data pointer for frame slot
     */
    void* getDataPtr(size_t index) {
        return data_pool_.get() + (index * frame_size_);
    }
};

/**
 * @brief Specialized queue for V4L2 buffer indices
 * 
 * Used for returning processed buffers back to capture thread
 * for requeuing. Much lighter weight than full frame queue.
 */
class BufferIndexQueue {
public:
    explicit BufferIndexQueue(size_t capacity);
    
    bool tryPush(uint32_t index);
    bool tryPop(uint32_t& index);
    bool empty() const;
    
private:
    std::unique_ptr<uint32_t[]> indices_;
    size_t capacity_;
    
    alignas(64) std::atomic<size_t> head_{0};
    alignas(64) std::atomic<size_t> tail_{0};
};

} // namespace ndi_bridge
