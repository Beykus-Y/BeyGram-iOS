// Hands the host tap from the main thread to the realtime render thread of BGMixPlayer.
//
// The render thread brackets each call into the tap with enter() and leave(). The main thread attaches,
// replaces or detaches the tap with set(). set() returns only after the render thread has left every call
// that loaded the previous pointer, so the owner may destroy the old tap once set() returns. Neither side
// locks or allocates. This is plain C++20 with no Objective-C, so the host test builds on Linux.
#pragma once

#include <atomic>
#include <thread>

namespace beygram::media {

template <typename Tap>
class PcmTapSlot {
public:
    // Realtime thread. Pair every enter() with one leave(), including when enter() returns nullptr.
    Tap *enter() noexcept {
        inFlight_.fetch_add(1, std::memory_order_seq_cst);
        return tap_.load(std::memory_order_seq_cst);
    }

    void leave() noexcept {
        inFlight_.fetch_sub(1, std::memory_order_seq_cst);
    }

    // Main thread. `tap` replaces the current one; nullptr detaches it. A call that enters after the store
    // loads the new pointer, and the wait may also see it. Such a call is short, so the wait stays short.
    void set(Tap *tap) noexcept {
        tap_.store(tap, std::memory_order_seq_cst);
        while (inFlight_.load(std::memory_order_seq_cst) != 0) {
            std::this_thread::yield();
        }
    }

private:
    std::atomic<Tap *> tap_{nullptr};
    // Calls between enter() and leave() on the render thread.
    std::atomic<int> inFlight_{0};
};

}  // namespace beygram::media
