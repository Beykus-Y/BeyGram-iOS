// Host test for Sources/BGMixPcmTapSlot.hpp. Plain CHECK + main(), like the other C++ units in this repo.

#include "../Sources/BGMixPcmTapSlot.hpp"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <memory>
#include <thread>
#include <vector>

namespace {

int failures = 0;

#define CHECK_TRUE(cond)                                                     \
    do {                                                                     \
        if (!(cond)) {                                                       \
            std::fprintf(stderr, "%s:%d: CHECK_TRUE(%s) failed\n", __FILE__, \
                         __LINE__, #cond);                                   \
            ++failures;                                                      \
        }                                                                    \
    } while (0)

using beygram::media::PcmTapSlot;

// A stand-in for the tap. The owner sets `detached` only after set() has returned, so a render-thread call
// that finds it set has broken the handoff.
struct FakeTap {
    std::atomic<bool> detached{false};
    std::atomic<long> calls{0};
};

void testDetachedSlotYieldsNothing() {
    PcmTapSlot<FakeTap> slot;
    CHECK_TRUE(slot.enter() == nullptr);
    slot.leave();
}

void testAttachReplaceDetach() {
    PcmTapSlot<FakeTap> slot;
    FakeTap a;
    FakeTap b;

    slot.set(&a);
    CHECK_TRUE(slot.enter() == &a);
    slot.leave();

    slot.set(&b);
    CHECK_TRUE(slot.enter() == &b);
    slot.leave();

    slot.set(nullptr);
    CHECK_TRUE(slot.enter() == nullptr);
    slot.leave();
}

// set() must not return while the render thread is still inside a call that loaded the old tap.
void testSetWaitsForRealtimeCall() {
    PcmTapSlot<FakeTap> slot;
    FakeTap tap;
    slot.set(&tap);

    std::atomic<bool> inside{false};
    std::atomic<bool> mayLeave{false};
    std::atomic<bool> setReturned{false};

    std::thread render([&] {
        if (slot.enter() != nullptr) {
            inside.store(true);
            while (!mayLeave.load()) {
                std::this_thread::yield();
            }
        }
        slot.leave();
    });

    while (!inside.load()) {
        std::this_thread::yield();
    }

    std::thread owner([&] {
        slot.set(nullptr);
        setReturned.store(true);
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    CHECK_TRUE(!setReturned.load());

    mayLeave.store(true);
    render.join();
    owner.join();
    CHECK_TRUE(setReturned.load());
}

// The render thread calls the tap in a tight loop while the owner replaces it many times. A tap whose
// owner has seen set() return must never be entered again. The taps stay allocated until the end, so the
// check reads only live objects.
void testReplacementUnderLoad() {
    PcmTapSlot<FakeTap> slot;
    std::vector<std::unique_ptr<FakeTap>> taps;
    taps.reserve(2001);

    std::atomic<bool> stop{false};
    std::atomic<long> violations{0};
    std::atomic<long> deliveries{0};

    std::thread render([&] {
        while (!stop.load(std::memory_order_relaxed)) {
            if (FakeTap *tap = slot.enter()) {
                if (tap->detached.load()) {
                    violations.fetch_add(1);
                }
                tap->calls.fetch_add(1);
                deliveries.fetch_add(1);
            }
            slot.leave();
        }
    });

    FakeTap *previous = nullptr;
    for (int round = 0; round < 2000; ++round) {
        taps.push_back(std::make_unique<FakeTap>());
        FakeTap *next = taps.back().get();
        slot.set(next);
        if (previous != nullptr) {
            previous->detached.store(true);
        }
        previous = next;
    }

    slot.set(nullptr);
    if (previous != nullptr) {
        previous->detached.store(true);
    }
    stop.store(true);
    render.join();

    CHECK_TRUE(violations.load() == 0);
    CHECK_TRUE(deliveries.load() > 0);
}

}  // namespace

int main() {
    testDetachedSlotYieldsNothing();
    testAttachReplaceDetach();
    testSetWaitsForRealtimeCall();
    testReplacementUnderLoad();
    if (failures != 0) {
        std::fprintf(stderr, "BGMixPcmTapSlotTests: %d check(s) failed\n", failures);
        return 1;
    }
    std::printf("BGMixPcmTapSlotTests: all checks passed\n");
    return 0;
}
