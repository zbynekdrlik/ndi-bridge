// DeckLinkStatistics.cpp
#include "capture/DeckLinkStatistics.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <algorithm>

DeckLinkStatistics::DeckLinkStatistics()
    : m_frameCount(0)
    , m_droppedFrames(0) {
}

void DeckLinkStatistics::Reset() {
    m_frameCount = 0;
    m_droppedFrames = 0;
    
    std::lock_guard<std::mutex> lock(m_historyMutex);
    m_frameHistory.clear();
}

void DeckLinkStatistics::RecordFrame() {
    m_frameCount++;
    
    // Store timestamp for rolling average
    std::lock_guard<std::mutex> lock(m_historyMutex);
    m_frameHistory.push_back({
        static_cast<int>(m_frameCount.load()),
        std::chrono::high_resolution_clock::now()
    });
    
    // Remove old entries (keep 60 seconds)
    auto cutoffTime = std::chrono::high_resolution_clock::now() - 
                     std::chrono::seconds(HISTORY_RETENTION_SECONDS);
    while (!m_frameHistory.empty() && m_frameHistory.front().timestamp < cutoffTime) {
        m_frameHistory.pop_front();
    }
}

void DeckLinkStatistics::RecordDroppedFrame() {
    m_droppedFrames++;
}

void DeckLinkStatistics::GetStatistics(CaptureStatistics& stats,
                                       const std::chrono::high_resolution_clock::time_point& captureStartTime) const {
    stats.capturedFrames = m_frameCount;
    stats.droppedFrames = m_droppedFrames;
    
    auto now = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        now - captureStartTime).count();
    
    if (elapsed > 0) {
        stats.averageFPS = static_cast<double>(m_frameCount) / elapsed;
    } else {
        stats.averageFPS = 0.0;
    }
    
    // Calculate rolling average FPS
    stats.currentFPS = CalculateRollingFPS();
}

double DeckLinkStatistics::CalculateRollingFPS() const {
    std::lock_guard<std::mutex> lock(m_historyMutex);
    
    if (m_frameHistory.size() < 2) {
        return 0.0;
    }
    
    // Calculate FPS over the last 5 seconds
    auto now = std::chrono::high_resolution_clock::now();
    auto cutoffTime = now - std::chrono::seconds(ROLLING_AVERAGE_SECONDS);
    
    // Find first frame after cutoff
    auto it = std::find_if(m_frameHistory.begin(), m_frameHistory.end(),
        [cutoffTime](const FrameTimestamp& ft) {
            return ft.timestamp >= cutoffTime;
        });
    
    if (it == m_frameHistory.end() || it == std::prev(m_frameHistory.end())) {
        return 0.0;
    }
    
    auto firstFrame = *it;
    auto lastFrame = m_frameHistory.back();
    
    auto timeDiff = std::chrono::duration_cast<std::chrono::milliseconds>(
        lastFrame.timestamp - firstFrame.timestamp).count();
    
    if (timeDiff <= 0) {
        return 0.0;
    }
    
    int frameDiff = lastFrame.frameNumber - firstFrame.frameNumber;
    return (static_cast<double>(frameDiff) * 1000.0) / timeDiff;
}

void DeckLinkStatistics::LogStatistics(int64_t frameTimescale, int64_t frameDuration) {
    try {
        double rollingFPS = CalculateRollingFPS();
        double expectedFPS = (frameDuration > 0) ? 
            static_cast<double>(frameTimescale) / static_cast<double>(frameDuration) : 0.0;
        
        std::stringstream ss;
        ss << "[DeckLink] Frames: " << m_frameCount.load();
        
        if (rollingFPS > 0) {
            ss << ", FPS: " << std::fixed << std::setprecision(2) << rollingFPS;
            if (expectedFPS > 0) {
                ss << " (Expected: " << std::fixed << std::setprecision(2) << expectedFPS << ")";
            }
        }
        
        if (m_droppedFrames > 0) {
            ss << ", Dropped: " << m_droppedFrames.load();
        }
        
        std::cout << ss.str() << std::endl;
    }
    catch (const std::exception& e) {
        std::cerr << "[DeckLink] Exception in LogStatistics: " << e.what() << std::endl;
    }
}

bool DeckLinkStatistics::ShouldLogStatistics() const {
    return (m_frameCount % LOG_INTERVAL_FRAMES) == 0;
}
