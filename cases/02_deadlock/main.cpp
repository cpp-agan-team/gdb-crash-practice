#include <atomic>
#include <iostream>
#include <mutex>
#include <thread>

struct WorkerEvidence {
    int worker_id;
    std::mutex* held;
    std::mutex* waiting_for;
};

std::mutex left_mutex;
std::mutex right_mutex;
std::atomic<unsigned> first_locks_held{0};
std::atomic<unsigned> second_locks_attempted{0};
WorkerEvidence worker_a{1, nullptr, nullptr};
WorkerEvidence worker_b{2, nullptr, nullptr};

// Teaching breakpoint: main calls this after both workers publish their state.
[[gnu::noinline]] void deadlock_ready() {}

void deadlock_worker(WorkerEvidence* evidence,
                     std::mutex* first, std::mutex* second) {
#ifdef FIX_BUG
    (void)evidence;
    // Both mutexes are acquired together with the deadlock-avoidance algorithm.
    std::scoped_lock both(*first, *second);
#else
    std::unique_lock<std::mutex> first_guard(*first);
    evidence->held = first;
    first_locks_held.fetch_add(1, std::memory_order_acq_rel);

    // Neither worker tries its second mutex until BOTH hold their first mutex.
    while (first_locks_held.load(std::memory_order_acquire) != 2) {
        std::this_thread::yield();
    }

    evidence->waiting_for = second;
    second_locks_attempted.fetch_add(1, std::memory_order_acq_rel);
    std::unique_lock<std::mutex> second_guard(*second);  // Deterministic deadlock.
#endif
}

int main() {
    std::cout << "Two workers acquire the same mutex pair in opposite orders.\n"
              << std::flush;
    std::thread a(deadlock_worker, &worker_a, &left_mutex, &right_mutex);
    std::thread b(deadlock_worker, &worker_b, &right_mutex, &left_mutex);
#ifndef FIX_BUG
    while (second_locks_attempted.load(std::memory_order_acquire) != 2) {
        std::this_thread::yield();
    }
    deadlock_ready();
#endif
    a.join();
    b.join();
    std::cout << "Both workers completed.\n";
}
