// Optimized V4L2 capture thread for stable 60fps and 8-frame latency
// Key optimizations:
// 1. Use poll() with proper timeout instead of pure busy-wait
// 2. Reduce buffer count from 8 to 4 for lower latency
// 3. Add frame pacing to maintain stable 60fps
// 4. Optimize EAGAIN handling

void V4L2Capture::captureThreadOptimized() {
    Logger::info("V4L2 Optimized capture thread started");
    
    // Apply real-time settings
    applyExtremeRealtimeSettings();
    
    // Frame timing for stable 60fps
    const auto frame_duration = std::chrono::microseconds(16667); // 60fps = 16.667ms
    auto next_frame_time = std::chrono::steady_clock::now();
    
    // Performance monitoring
    auto last_stats_time = std::chrono::steady_clock::now();
    uint64_t frame_count = 0;
    uint64_t total_frames = 0;
    uint64_t dropped_frames = 0;
    
    // FPS calculation
    const int fps_window = 60;
    std::chrono::steady_clock::time_point fps_start_time = std::chrono::steady_clock::now();
    uint64_t fps_frame_count = 0;
    
    // Use poll for efficient waiting
    struct pollfd pfd;
    pfd.fd = fd_;
    pfd.events = POLLIN;
    
    // Pre-allocate v4l2_buffer to avoid repeated allocation
    v4l2_buffer v4l2_buf = {};
    v4l2_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    v4l2_buf.memory = buffer_type_;
    
    while (!should_stop_) {
        // Calculate time until next frame
        auto now = std::chrono::steady_clock::now();
        auto time_until_next = next_frame_time - now;
        
        // Use poll with dynamic timeout
        int timeout_ms = 1; // Default 1ms
        if (time_until_next > std::chrono::milliseconds(0)) {
            timeout_ms = std::chrono::duration_cast<std::chrono::milliseconds>(time_until_next).count();
            timeout_ms = std::max(0, std::min(timeout_ms, 16)); // Cap at frame time
        }
        
        int ret = poll(&pfd, 1, timeout_ms);
        
        if (ret < 0) {
            if (errno == EINTR) continue;
            setError("Poll error: " + std::string(strerror(errno)));
            break;
        }
        
        if (ret == 0) {
            // Timeout - check if we missed a frame
            if (now > next_frame_time + frame_duration) {
                dropped_frames++;
                next_frame_time = now; // Reset timing
            }
            continue;
        }
        
        // Data available - dequeue buffer
        if (ioctl(fd_, VIDIOC_DQBUF, &v4l2_buf) < 0) {
            if (errno == EAGAIN) {
                // This should be rare with poll
                continue;
            }
            setError("Failed to dequeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        // Process frame with zero-copy
        auto capture_time = std::chrono::steady_clock::now();
        sendFrameExtreme(buffers_[v4l2_buf.index], v4l2_buf, capture_time);
        
        // Requeue buffer immediately
        if (ioctl(fd_, VIDIOC_QBUF, &v4l2_buf) < 0) {
            setError("Failed to requeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        // Update frame timing
        frame_count++;
        total_frames++;
        fps_frame_count++;
        
        // Maintain 60fps pacing
        next_frame_time += frame_duration;
        
        // If we're behind, catch up but don't accumulate delay
        now = std::chrono::steady_clock::now();
        if (now > next_frame_time + frame_duration * 2) {
            next_frame_time = now;
        }
        
        // Calculate FPS over window
        if (fps_frame_count >= fps_window) {
            auto fps_duration = std::chrono::steady_clock::now() - fps_start_time;
            double fps = fps_frame_count * 1000000000.0 / 
                        std::chrono::duration_cast<std::chrono::nanoseconds>(fps_duration).count();
            
            Logger::info("Actual FPS: " + std::to_string(fps) + 
                        " (target: 60.0), dropped: " + std::to_string(dropped_frames));
            
            fps_frame_count = 0;
            fps_start_time = std::chrono::steady_clock::now();
        }
        
        // Log statistics every 5 seconds
        if (now - last_stats_time >= std::chrono::seconds(5)) {
            Logger::info("Frame stats - Captured: " + std::to_string(total_frames) +
                        ", Sent: " + std::to_string(total_frames - dropped_frames) +
                        ", Dropped: " + std::to_string(dropped_frames) +
                        " (" + std::to_string(100.0 * dropped_frames / total_frames) + "%)");
            
            last_stats_time = now;
        }
    }
    
    Logger::info("V4L2 capture thread stopped");
    Logger::info("Final stats - Total frames: " + std::to_string(total_frames) +
                ", Dropped: " + std::to_string(dropped_frames));
}

// Optimized buffer configuration
bool V4L2Capture::setupBuffersOptimized() {
    // Request only 4 buffers for lower latency (8-frame roundtrip target)
    v4l2_requestbuffers req;
    memset(&req, 0, sizeof(req));
    req.count = 4; // Reduced from 8
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    
    if (ioctl(fd_, VIDIOC_REQBUFS, &req) < 0) {
        setError("Failed to request buffers: " + std::string(strerror(errno)));
        return false;
    }
    
    if (req.count < 2) {
        setError("Insufficient buffer memory");
        return false;
    }
    
    buffer_count_ = req.count;
    buffers_.resize(buffer_count_);
    
    // Map buffers
    for (unsigned int i = 0; i < buffer_count_; i++) {
        v4l2_buffer buf;
        memset(&buf, 0, sizeof(buf));
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        
        if (ioctl(fd_, VIDIOC_QUERYBUF, &buf) < 0) {
            setError("Failed to query buffer: " + std::string(strerror(errno)));
            return false;
        }
        
        buffers_[i].length = buf.length;
        buffers_[i].start = mmap(NULL, buf.length,
                                PROT_READ | PROT_WRITE,
                                MAP_SHARED,
                                fd_, buf.m.offset);
        
        if (buffers_[i].start == MAP_FAILED) {
            setError("Failed to map buffer: " + std::string(strerror(errno)));
            return false;
        }
        
        // Pre-fault pages for lower latency
        if (mlock(buffers_[i].start, buf.length) == 0) {
            // Touch pages to fault them in
            volatile char* p = (volatile char*)buffers_[i].start;
            for (size_t j = 0; j < buf.length; j += 4096) {
                p[j] = 0;
            }
        }
    }
    
    Logger::info("V4L2Capture: Setup " + std::to_string(buffer_count_) + 
                " buffers (optimized for 8-frame latency)");
    return true;
}