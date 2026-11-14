#include "motolink/ble.hpp"
#include <cstdlib>
#include <cstring>

static void check(bool condition) { if (!condition) std::abort(); }

int main() {
  motolink::Ble ble;
  check(ble.mode() == motolink::Ble::Mode::off);
  check(ble.state() == motolink::Ble::State::off);
  
  // Test payload sizes
  check(sizeof(motolink::Ble::NavPayload) == 16);
  check(sizeof(motolink::Ble::ImuPayload) == 16);
  check(sizeof(motolink::Ble::CommandFrame) == 20);
  check(sizeof(motolink::Ble::ConfigFrame) == 20);
  check(sizeof(motolink::Ble::InfoFrame) == 44);
  
  // Test CRC8
  uint8_t data[] = {0x01, 0x02, 0x03, 0x04};
  uint8_t crc = motolink::Ble::crc8(data, 4);
  check(crc == 0x1D);  // Known CRC8 result for this data
}

