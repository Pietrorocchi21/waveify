#include "motolink/status.hpp"
#include <cstdlib>

static void check(bool condition) { if (!condition) std::abort(); }

int main() {
  motolink::StatusLed led;
  motolink::ServiceButton btn;
  
  // Test LED patterns
  check(motolink::LedPattern::off == 0);
  check(motolink::LedPattern::solid_on == 1);
  check(motolink::LedPattern::slow_blink == 2);
  check(motolink::LedPattern::fast_blink == 3);
  check(motolink::LedPattern::heartbeat == 4);
  check(motolink::LedPattern::breathing == 5);
  check(motolink::LedPattern::triple_blink == 6);
  
  // Test Button events
  check(motolink::ButtonEvent::none == 0);
  check(motolink::ButtonEvent::short_press == 1);
  check(motolink::ButtonEvent::long_press == 2);
  check(motolink::ButtonEvent::very_long_press == 3);
  check(motolink::ButtonEvent::double_click == 4);
}

