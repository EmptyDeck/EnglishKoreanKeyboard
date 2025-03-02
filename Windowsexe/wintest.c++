#include <iostream>
#include <chrono>
#include <thread>

int main() {
    std::cout << "Starting the test program..." << std::endl;

    // Simulate some work or delay
    std::cout << "Performing some simulated work..." << std::endl;
    for (int i = 0; i < 5; ++i) {
        std::cout << ".";
        std::cout.flush(); // Force output to appear immediately
        std::this_thread::sleep_for(std::chrono::milliseconds(500)); // Sleep for 500ms
    }
    std::cout << std::endl;

    // Display a message with some dynamic information
    auto now = std::chrono::system_clock::now();
    std::time_t now_time = std::chrono::system_clock::to_time_t(now);
    std::cout << "Current time: " << std::ctime(&now_time);

    std::cout << "Test program completed successfully!" << std::endl;

    // Optionally, pause to see the output (especially on Windows)
    std::cout << "Press Enter to exit...";
    std::cin.get(); // Wait for user input

    return 0;
}