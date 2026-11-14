#include "motolink/core.hpp"
#include <cstdlib>

static void check(bool condition) {
  if (!condition) std::abort();
}

int main() {
  motolink::Core core;
  core.begin(0xfffffff0u);
  check(core.status().state == motolink::State::booting);
  core.tick(0x10u);
  check(core.status().uptime_ms == 32u);
  core.initialization_complete();
  check(core.status().state == motolink::State::ready);
  check(core.handle(motolink::Command::ping).accepted);
  check(core.handle(motolink::Command::get_status).accepted);
  check(!core.handle(motolink::Command::unknown).accepted);
  core.fail(42);
  core.initialization_complete();
  core.fail(99);
  check(core.status().state == motolink::State::fault);
  check(core.status().fault_code == 42);
  core.begin(100);
  check(core.status().fault_code == 0);
  check(core.status().uptime_ms == 0);
  core.fail(0);
  check(core.status().fault_code != 0);
}
