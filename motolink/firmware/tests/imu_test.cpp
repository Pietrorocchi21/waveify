#include "motolink/imu.hpp"
#include <cstdlib>

static void check(bool condition) { if (!condition) std::abort(); }

int main() {
  motolink::Imu imu;
  check(imu.mode() == motolink::Imu::Mode::off);
  // begin() requires hardware, so just test structure
  auto sample = imu.read(1000);
  check(!sample.valid);  // Not initialized
  check(imu.self_test() == false);  // Not initialized
}

