#include <iostream>

namespace demo {
struct Invoice {
    int quantity;
    int unit_price;
    int total;
};

// The invoice is already initialized when this function is entered.
void ready_for_watch(Invoice& invoice) {
    (void)invoice;
}

void apply_discount(Invoice& invoice, int discount) {
#ifdef FIX_BUG
    invoice.total -= discount;
#else
    invoice.total = discount;  // BUG: overwrite the total instead of subtracting.
#endif
}
}  // namespace demo

int main() {
    demo::Invoice invoice{3, 100, 300};
    const int discount = 30;
    demo::ready_for_watch(invoice);
    demo::apply_discount(invoice, discount);
    const int expected = invoice.quantity * invoice.unit_price - discount;
    std::cout << "total=" << invoice.total << " expected=" << expected << '\n';
    return invoice.total == expected ? 0 : 1;
}
