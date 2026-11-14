#pragma once
#include <cstdint>

namespace motolink {

enum class LedPattern : uint8_t {
  off = 0,
  solid_on = 1,
  slow_blink = 2,      // 1 Hz - booting, no GPS
  fast_blink = 3,      // 4 Hz - error/fault
  heartbeat = 4,       // Double blink - ready, GPS ok
  breathing = 5,       // PWM fade - ready, no GPS
  triple_blink = 6     // 3 quick blinks - BLE connected
};

class StatusLed {
 public:
  void begin(uint8_t gpio, bool active_high = true);
  void end();
  void set_pattern(LedPattern pattern);
  void set_brightness(uint8_t brightness);  // 0-255
  void update(uint32_t now_ms);
  
 private:
  uint8_t gpio_ = 0xFF;
  bool active_high_ = true;
  LedPattern pattern_ = LedPattern::off;
  uint8_t brightness_ = 255;
  bool initialized_ = false;
  
  // Blink state
  uint32_t last_change_ms_ = 0;
  bool led_state_ = false;
  uint8_t blink_step_ = 0;
  uint32_t pattern_start_ms_ = 0;
};

enum class ButtonEvent : uint8_t {
  none = 0,
  short_press = 1,     // < 1s
  long_press = 2,      // 1-3s
  very_long_press = 3, // > 3s
  double_click = 4
};

class ServiceButton {
 public:
  void begin(uint8_t gpio, bool active_low = true);
  void end();
  ButtonEvent poll(uint32_t now_ms);
  
 private:
  uint8_t gpio_ = 0xFF;
  bool active_low_ = true;
  bool initialized_ = false;
  
  // Debounce and timing
  bool last_state_ = false;
  bool stable_state_ = false;
  uint32_t last_change_ms_ = 0;
  uint32_t press_start_ms_ = 0;
  uint32_t last_release_ms_ = 0;
  uint8_t click_count_ = 0;
  
  static constexpr uint32_t DEBOUNCE_MS = 20;
  static constexpr uint32_t LONG_PRESS_MS = 1000;
  static constexpr uint32_t VERY_LONG_PRESS_MS = 3000;
  static constexpr uint32_t DOUBLE_CLICK_MS = 400;
};

}  // namespace motolink
