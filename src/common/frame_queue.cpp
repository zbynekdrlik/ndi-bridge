#include "frame_queue.h"
#include "logger.h"
#include <algorithm>

namespace ndi_bridge {

FrameQueue::FrameQueue(size_t capacity, size_t frame_size)
    : frame_size_(frame_size)
    , capacity_(capacity) {
    
    // Allocate frame metadata array
    frames_ = std::make_unique<Frame[]>(capacity);
    
    // Allocate contiguous memory pool for all frame data
    data_pool_ = std::make_unique<uint8_t[]>(capacity * frame_size);
    
    Logger::debug("FrameQueue: Created with capacity " + std::to_string(capacity) + 
                 ", frame size " + std::to_string(frame_size) + " bytes");
}

FrameQueue::~FrameQueue() {
    Logger::debug("FrameQueue: Destroyed, dropped frames: " + 
                 std::to_string(dropped_frames_.load()));
}

bool FrameQueue::tryPush(const Frame& frame) {
    size_t current_tail = tail_.load(std::memory_order_relaxed);
    size_t next_tail = (current_tail + 1) % capacity_;
    
    // Check if full (would overrun head)
    if (next_tail == head_.load(std::memory_order_acquire)) {
        dropped_frames_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    
    // Get slot and copy frame data
    Frame& slot = frames_[current_tail];
    slot = frame;
    
    // Copy frame data to our buffer pool
    void* dest = getDataPtr(current_tail);
    if (frame.data && frame.size > 0) {
        size_t copy_size = std::min(frame.size, frame_size_);
        memcpy(dest, frame.data, copy_size);
        slot.data = dest;
        slot.size = copy_size;
    }
    
    // Commit the push
    tail_.store(next_tail, std::memory_order_release);
    return true;
}

bool FrameQueue::tryPop(Frame& frame) {
    size_t current_head = head_.load(std::memory_order_relaxed);
    
    // Check if empty
    if (current_head == tail_.load(std::memory_order_acquire)) {
        return false;
    }
    
    // Read frame
    frame = frames_[current_head];
    
    // Move head forward
    size_t next_head = (current_head + 1) % capacity_;
    head_.store(next_head, std::memory_order_release);
    
    return true;
}

bool FrameQueue::empty() const {
    return head_.load(std::memory_order_acquire) == 
           tail_.load(std::memory_order_acquire);
}

bool FrameQueue::full() const {
    size_t current_tail = tail_.load(std::memory_order_acquire);
    size_t next_tail = (current_tail + 1) % capacity_;
    return next_tail == head_.load(std::memory_order_acquire);
}

size_t FrameQueue::size() const {
    size_t h = head_.load(std::memory_order_acquire);
    size_t t = tail_.load(std::memory_order_acquire);
    
    if (t >= h) {
        return t - h;
    } else {
        return capacity_ - h + t;
    }
}

// BufferIndexQueue implementation

BufferIndexQueue::BufferIndexQueue(size_t capacity)
    : capacity_(capacity) {
    indices_ = std::make_unique<uint32_t[]>(capacity);
}

bool BufferIndexQueue::tryPush(uint32_t index) {
    size_t current_tail = tail_.load(std::memory_order_relaxed);
    size_t next_tail = (current_tail + 1) % capacity_;
    
    if (next_tail == head_.load(std::memory_order_acquire)) {
        return false;
    }
    
    indices_[current_tail] = index;
    tail_.store(next_tail, std::memory_order_release);
    return true;
}

bool BufferIndexQueue::tryPop(uint32_t& index) {
    size_t current_head = head_.load(std::memory_order_relaxed);
    
    if (current_head == tail_.load(std::memory_order_acquire)) {
        return false;
    }
    
    index = indices_[current_head];
    size_t next_head = (current_head + 1) % capacity_;
    head_.store(next_head, std::memory_order_release);
    return true;
}

bool BufferIndexQueue::empty() const {
    return head_.load(std::memory_order_acquire) == 
           tail_.load(std::memory_order_acquire);
}

} // namespace ndi_bridge
