#include "motolink/can.hpp"
#include <cstdlib>
#include <cstring>

static void check(bool condition) { if (!condition) std::abort(); }

int main() {
  motolink::Can can;
  check(can.mode() == motolink::Can::Mode::off);
  check(can.state() == motolink::Can::State::uninitialized);
  check(can.rx_count() == 0);
  check(can.tx_count() == 0);
  check(can.available() == 0);
  
  // Test struct sizes
  check(sizeof(motolink::Can::CanFrame) == 24);
  check(sizeof(motolink::Can::CanFilter) == 16);
  
  // Test frame format
  motolink::Can::CanFrame frame = {};
  frame.id = 0x123;
  frame.dlc = 8;
  frame.format = motolink::CanFormat::standard;
  frame.rtr = false;
  frame.timestamp_ms = 1000;
  check(frame.id == 0x123);
  check(frame.format == motolink::CanFormat::standard);
}

