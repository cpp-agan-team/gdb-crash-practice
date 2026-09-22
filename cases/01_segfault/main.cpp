#include <iostream>

struct Order {
    int quantity;
    int unit_price;
};

int calculate_total(const Order* order) {
    // Intentional teaching bug: the caller passes nullptr.
    return order->quantity * order->unit_price;
}

int process_request(const Order* order) {
    return calculate_total(order);
}

int main() {
    const Order* order = nullptr;
    std::cout << "total=" << process_request(order) << '\n';
}
