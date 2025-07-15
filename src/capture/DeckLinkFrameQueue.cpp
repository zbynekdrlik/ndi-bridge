// DeckLinkFrameQueue.cpp
#include "capture/DeckLinkFrameQueue.h"
#include <cstring>

DeckLinkFrameQueue::DeckLinkFrameQueue()
    : m_isCapturing(true) {
}

DeckLinkFrameQueue::~DeckLinkFrameQueue() {
    Clear();
}

void DeckLinkFrameQueue::AddFrame(const void* frameData, size_t frameSize,
                                  int width, int height,
                                  BMDPixelFormat pixelFormat,
                                  std::atomic<uint64_t>& droppedFrames) {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    // Drop oldest frame if queue is full
    if (m_queue.size() >= MAX_QUEUE_SIZE) {
        m_queue.pop_front();
        droppedFrames++;
    }
    
    // Add new frame
    QueuedFrame frame;
    frame.data.resize(frameSize);
    std::memcpy(frame.data.data(), frameData, frameSize);
    frame.width = width;
    frame.height = height;
    frame.pixelFormat = pixelFormat;
    frame.timestamp = std::chrono::steady_clock::now();
    
    m_queue.push_back(std::move(frame));
    
    // Notify waiting threads
    m_frameAvailable.notify_one();
}

bool DeckLinkFrameQueue::GetNextFrame(QueuedFrame& frame, int timeoutMs) {
    std::unique_lock<std::mutex> lock(m_mutex);
    
    // Wait for frame with timeout
    if (!m_frameAvailable.wait_for(lock, std::chrono::milliseconds(timeoutMs),
                                  [this] { return !m_queue.empty() || !m_isCapturing; })) {
        return false;
    }
    
    if (m_queue.empty() || !m_isCapturing) {
        return false;
    }
    
    // Get frame from queue
    frame = std::move(m_queue.front());
    m_queue.pop_front();
    
    return true;
}

void DeckLinkFrameQueue::Clear() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.clear();
    m_frameAvailable.notify_all();
}

bool DeckLinkFrameQueue::IsEmpty() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_queue.empty();
}

size_t DeckLinkFrameQueue::GetSize() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_queue.size();
}

void DeckLinkFrameQueue::StopCapture() {
    m_isCapturing = false;
    m_frameAvailable.notify_all();
}
