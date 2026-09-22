#include <iostream>

// Inputs in this example are small, non-negative, and count is nonzero.
double divide_total(int total, int count) {
    // Intentional teaching bug: integer division occurs before conversion to double.
    return total / count;
}

double average_score(const int* values, int count) {
    int total = 0;
    for (int i = 0; i < count; ++i) {
        total += values[i];
    }
    return divide_total(total, count);
}

void display_result(double actual) {
    const double expected = 11.75;
    std::cout << "actual=" << actual << " expected=" << expected
              << " match=" << std::boolalpha << (actual == expected) << '\n';
}

int main() {
    const int values[] = {10, 11, 12, 14};
    const double result = average_score(values, 4);
    display_result(result);
}
