#include "motolink/storage.hpp"
#include <cstdlib>
#include <cstring>

static void check(bool condition) { if (!condition) std::abort(); }

int main() {
  motolink::Storage storage;
  check(storage.state() == motolink::StorageState::unmounted);
  check(!storage.is_card_present());
  check(storage.free_bytes() == 0);
  check(storage.total_bytes() == 0);
  
  // Test struct sizes
  check(sizeof(motolink::Storage::LogHeader) == 24);
  check(sizeof(motolink::Storage::GnssEntry) == 24);
  check(sizeof(motolink::Storage::ImuEntry) == 20);
  check(sizeof(motolink::Storage::EventEntry) == 12);
  
  // Test event codes
  check(motolink::Storage::EVT_BOOT == 0x0001);
  check(motolink::Storage::EVT_GNSS_FIX == 0x0010);
  check(motolink::Storage::EVT_ERROR == 0xFFFF);
}

