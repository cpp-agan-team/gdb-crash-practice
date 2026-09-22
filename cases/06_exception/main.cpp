#include <exception>
#include <iostream>
#include <stdexcept>

namespace demo {
int parse_worker_count(int raw_count) {
    if (raw_count <= 0) {
        throw std::runtime_error("worker count must be positive");
    }
    return raw_count;
}

void start_server(int configured_count) {
    const int workers = parse_worker_count(configured_count);
    std::cout << "server ready: workers=" << workers << '\n';
}
}  // namespace demo

int main() {
    const int configured_count = -2;
#ifdef FIX_BUG
    try {
        demo::start_server(configured_count);
    } catch (const std::exception& error) {
        std::cerr << "configuration error: " << error.what() << '\n';
        return 2;
    }
#else
    demo::start_server(configured_count);  // BUG: no handler at the application boundary.
#endif
    return 0;
}
