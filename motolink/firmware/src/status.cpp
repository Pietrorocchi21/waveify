#include "motolink/status.hpp"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_log.h"

namespace motolink {

static constexpr char tag[] = "status";

void StatusLed::begin(uint8_t gpio, bool active_high) {
  gpio_ = gpio;
  active_high_ = active_high;
  pattern_ = LedPattern::off;
  brightness_ = 255;
  led_state_ = false;
  last_change_ms_ = 0;
  blink_step_ = 0;
  pattern_start_ms_ = 0;
  initialized_ = true;

  gpio_config_t io_conf = {};
  io_conf.intr_type = GPIO_INTR_DISABLE;
  io_conf.mode = GPIO_MODE_OUTPUT;
  io_conf.pin_bit_mask = (1ULL << gpio_);
  io_conf.pull_down_en = GPIO_PULLDOWN_DISABLE;
  io_conf.pull_up_en = GPIO_PULLUP_DISABLE;
  gpio_config(&io_conf);

  ledc_timer_config_t timer_conf = {};
  timer_conf.speed_mode = LEDC_LOW_SPEED_MODE;
  timer_conf.duty_resolution = LEDC_TIMER_8_BIT;
  timer_conf.timer_num = LEDC_TIMER_0;
  timer_conf.freq_hz = 5000;
  ledc_timer_config(&timer_conf);

  ledc_channel_config_t ch_conf = {};
  ch_conf.gpio_num = gpio_;
  ch_conf.speed_mode = LEDC_LOW_SPEED_MODE;
  ch_conf.channel = LEDC_CHANNEL_0;
  ch_conf.intr_type = LEDC_INTR_DISABLE;
  ch_conf.timer_sel = LEDC_TIMER_0;
  ch_conf.duty = 0;
  ch_conf.hpoint = 0;
  ledc_channel_config(&ch_conf);
}

void StatusLed::end() {
  if (!initialized_) return;
  ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, 0);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
  initialized_ = false;
}

void StatusLed::set_pattern(LedPattern pattern) {
  if (pattern_ == pattern) return;
  pattern_ = pattern;
  blink_step_ = 0;
  pattern_start_ms_ = 0;
  last_change_ms_ = 0;
}

void StatusLed::set_brightness(uint8_t brightness) {
  brightness_ = brightness;
}

void StatusLed::update(uint32_t now_ms) {
  if (!initialized_) return;

  uint32_t duty = 0;

  switch (pattern_) {
    case LedPattern::off:
      duty = 0;
      break;
    case LedPattern::solid_on:
      duty = brightness_;
      break;
    case LedPattern::slow_blink: {
      uint32_t elapsed = (now_ms - pattern_start_ms_) % 1000;
      duty = (elapsed < 500) ? brightness_ : 0;
      break;
    }
    case LedPattern::fast_blink: {
      uint32_t elapsed = (now_ms - pattern_start_ms_) % 250;
      duty = (elapsed < 125) ? brightness_ : 0;
      break;
    }
    case LedPattern::heartbeat: {
      uint32_t elapsed = (now_ms - pattern_start_ms_) % 2000;
      if (elapsed < 100 || (elapsed > 300 && elapsed < 400)) duty = brightness_;
      else if (elapsed < 200 || (elapsed > 600 && elapsed < 700)) duty = brightness_ / 2;
      else duty = 0;
      break;
    }
    case LedPattern::breathing: {
      uint32_t elapsed = (now_ms - pattern_start_ms_) % 2000;
      uint8_t phase = (elapsed * 255) / 2000;
      duty = (phase < 128) ? (phase * 2) : ((255 - phase) * 2);
      duty = (duty * brightness_) / 255;
      break;
    }
    case LedPattern::triple_blink: {
      uint32_t elapsed = (now_ms - pattern_start_ms_) % 2000;
      if (elapsed < 80 || (elapsed > 160 && elapsed < 240) || (elapsed > 320 && elapsed < 400)) {
        duty = brightness_;
      } else if (elapsed < 2000 && elapsed > 400) {
        duty = 0;
      } else {
        duty = 0;
      }
      break;
    }
  }

  if (!active_high_) duty = 255 - duty;
  ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, duty);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
}

void ServiceButton::begin(uint8_t gpio, bool active_low) {
  gpio_ = gpio;
  active_low_ = active_low;
  last_state_ = active_low;
  stable_state_ = active_low;
  last_change_ms_ = 0;
  press_start_ms_ = 0;
  last_release_ms_ = 0;
  click_count_ = 0;
  initialized_ = true;

  gpio_config_t io_conf = {};
  io_conf.intr_type = GPIO_INTR_DISABLE;
  io_conf.mode = GPIO_MODE_INPUT;
  io_conf.pin_bit_mask = (1ULL << gpio_);
  io_conf.pull_up_en = active_low ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE;
  io_conf.pull_down_en = active_low ? GPIO_PULLDOWN_DISABLE : GPIO_PULLDOWN_ENABLE;
  gpio_config(&io_conf);
}

void ServiceButton::end() {
  if (!initialized_) return;
  initialized_ = false;
}

ButtonEvent ServiceButton::poll(uint32_t now_ms) {
  if (!initialized_) return ButtonEvent::none;

  bool raw_state = gpio_get_level(gpio_);
  bool pressed = active_low_ ? !raw_state : raw_state;

  if (pressed != last_state_) {
    last_state_ = pressed;
    last_change_ms_ = now_ms;
    return ButtonEvent::none;
  }

  if (pressed != stable_state_) {
    if (now_ms - last_change_ms_ >= DEBOUNCE_MS) {
      stable_state_ = pressed;
      if (pressed) {
        press_start_ms_ = now_ms;
      } else {
        uint32_t press_duration = now_ms - press_start_ms_;
        last_release_ms_ = now_ms;

        if (press_duration >= VERY_LONG_PRESS_MS) {
          click_count_ = 0;
          return ButtonEvent::very_long_press;
        } else if (press_duration >= LONG_PRESS_MS) {
          click_count_ = 0;
          return ButtonEvent::long_press;
        } else {
          click_count_++;
          if (click_count_ == 2 && (now_ms - last_release_ms_ < DOUBLE_CLICK_MS)) {
            click_count_ = 0;
            return ButtonEvent::double_click;
          }
        }
      }
    }
  } else if (!pressed && click_count_ == 1) {
    if (now_ms - last_release_ms_ >= DOUBLE_CLICK_MS) {
      click_count_ = 0;
      return ButtonEvent::short_press;
    }
  }

  return ButtonEvent::none;
}

}  // namespace motolink
