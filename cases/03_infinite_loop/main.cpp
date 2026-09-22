#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>

constexpr std::array<unsigned, 8> items{{4, 9, 15, 0, 21, 25, 32, 40}};

struct Result {
    std::size_t processed;
    std::uint64_t checksum;
    std::uint64_t zero_hits;
};

// Teaching breakpoint: reached exactly when progress first gets stuck.
[[gnu::noinline]] void infinite_loop_ready() {}

[[gnu::noinline]] Result process_items() {
    std::size_t index = 0;
    std::uint64_t checksum = 0;
    volatile std::uint64_t zero_hits = 0;
    while (index < items.size()) {
        const unsigned value = items[index];
        if (value == 0) {
#ifndef FIX_BUG
            if (zero_hits == 0) {
                infinite_loop_ready();
            }
#endif
            ++zero_hits;  // Unsigned wraparound is defined, not signed overflow.
#ifdef FIX_BUG
            ++index;
#endif
            continue;    // BUG: index does not advance along this branch.
        }
        checksum += value;
        ++index;
    }
    return {index, checksum, zero_hits};
}

int main() {
    std::cout << "Processing 8 items; one item has value zero.\n" << std::flush;
    const Result result = process_items();
    std::cout << "completed index=" << result.processed
              << " checksum=" << result.checksum
              << " zero_hits=" << result.zero_hits << '\n';
    return result.processed == items.size() && result.checksum == 146 ? 0 : 1;
}
