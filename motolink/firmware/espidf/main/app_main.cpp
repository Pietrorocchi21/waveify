#include <cstdio>
#include <cstring>
#include <cstdint>
#include "sdkconfig.h"
#include "driver/uart.h"
#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_task_wdt.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "motolink/core.hpp"
#include "motolink/nmea.hpp"
#include "motolink/imu.hpp"
#include "motolink/ble.hpp"
#include "motolink/storage.hpp"
#include "motolink/can.hpp"
#include "motolink/status.hpp"
#include "motolink/board.hpp"

namespace {
constexpr char tag[] = "motolink";
motolink::Core core;
motolink::Nmea gnss;
motolink::Imu imu;
motolink::Ble ble;
motolink::Storage storage;
motolink::Can can;
motolink::StatusLed status_led;
motolink::ServiceButton service_btn;

std::uint32_t now_ms() {
  return static_cast<std::uint32_t>(esp_timer_get_time() / 1000);
}

void print_json_status(uint32_t now) {
  const auto status = core.status();
  const auto nav = gnss.navigation(now);
  const auto imu_sample = imu.read(now);
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  
  std::printf("{\"state\":%u,\"fault\":%u,\"uptime_ms\":%lu,"
              "\"heap_free\":%lu,\"gnss_enabled\":%s,\"fix\":%s,"
              "\"imu\":\"%s\",\"ble\":\"%s\",\"storage\":\"%s\",\"can\":\"%s\","
              "\"mac\":\"%02X%02X%02X%02X%02X%02X\"}\n",
              static_cast<unsigned>(status.state), status.fault_code,
              static_cast<unsigned long>(status.uptime_ms),
              static_cast<unsigned long>(esp_get_free_heap_size()),
              (CONFIG_MOTOLINK_GNSS_ENABLED) ? "true" : "false", nav.valid ? "true" : "false",
              (CONFIG_MOTOLINK_IMU_ENABLED) ? "active" : "off",
              (CONFIG_MOTOLINK_BLE_ENABLED) ? "advertising" : "off",
              (CONFIG_MOTOLINK_STORAGE_ENABLED) ? "mounted" : "off",
              (CONFIG_MOTOLINK_CAN_ENABLED) ? "running" : "off",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  std::fflush(stdout);
}

void command(const char* line, uint32_t now) {
  const auto status = core.status();
  const auto nav = gnss.navigation(now);
  const auto imu_sample = imu.read(now);
  
  if (std::strcmp(line, "PING") == 0) {
    std::printf("{\"reply\":\"PONG\",\"protocol\":1}\n");
  } else if (std::strcmp(line, "STATUS") == 0) {
    print_json_status(now);
  } else if (std::strcmp(line, "GNSS") == 0) {
    if (!nav.valid) std::printf("{\"fix\":false}\n");
    else std::printf("{\"fix\":true,\"lat\":%.7f,\"lon\":%.7f,\"speed_kmh\":%.2f}\n",
                     nav.latitude, nav.longitude, nav.speed_kmh);
  } else if (std::strcmp(line, "IMU") == 0) {
    if (!imu_sample.valid) std::printf("{\"valid\":false}\n");
    else std::printf("{\"valid\":true,\"ax\":%d,\"ay\":%d,\"az\":%d,\"gx\":%d,\"gy\":%d,\"gz\":%d}\n",
                     imu_sample.ax, imu_sample.ay, imu_sample.az,
                     imu_sample.gx, imu_sample.gy, imu_sample.gz);
  } else if (std::strcmp(line, "VERSION") == 0) {
    std::printf("{\"firmware\":\"MotoLink\",\"version\":\"%s\",\"protocol\":1}\n",
                esp_app_get_description()->version);
  } else if (std::strncmp(line, "LED ", 4) == 0) {
    int pattern = std::atoi(line + 4);
    if (pattern >= 0 && pattern <= 6) {
      status_led.set_pattern(static_cast<motolink::LedPattern>(pattern));
      std::printf("{\"led_pattern\":%d}\n", pattern);
    } else {
      std::printf("{\"error\":\"invalid_pattern\"}\n");
    }
  } else if (std::strcmp(line, "STORAGE_INFO") == 0) {
    std::printf("{\"free\":%lu,\"total\":%lu,\"present\":%s}\n",
                static_cast<unsigned long>(storage.free_bytes()),
                static_cast<unsigned long>(storage.total_bytes()),
                storage.is_card_present() ? "true" : "false");
  } else if (std::strncmp(line, "CAN_FILTER ", 11) == 0) {
    unsigned idx, id, mask;
    if (std::sscanf(line + 11, "%u %u %u", &idx, &id, &mask) == 3) {
      motolink::CanFilter filter = {};
      filter.id = id;
      filter.mask = mask;
      filter.format = motolink::CanFormat::standard;
      filter.enabled = true;
      if (can.set_filter(idx, filter)) {
        std::printf("{\"filter\":%u,\"id\":%u,\"mask\":%u}\n", idx, id, mask);
      } else {
        std::printf("{\"error\":\"filter_failed\"}\n");
      }
    } else {
      std::printf("{\"error\":\"usage: CAN_FILTER <idx> <id> <mask>\"}\n");
    }
  } else {
    std::printf("{\"error\":\"unknown_command\"}\n");
  }
  std::fflush(stdout);
}
}

extern "C" void app_main() {
  const uint32_t boot_time = now_ms();
  core.begin(boot_time);
  
  // Console uses the DevKit USB-to-UART connector (UART0, 115200).
  uart_config_t console_config = {};
  console_config.baud_rate = 115200;
  console_config.data_bits = UART_DATA_8_BITS;
  console_config.parity = UART_PARITY_DISABLE;
  console_config.stop_bits = UART_STOP_BITS_1;
  console_config.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;
  console_config.source_clk = UART_SCLK_DEFAULT;
  ESP_ERROR_CHECK(uart_param_config(UART_NUM_0, &console_config));
  ESP_ERROR_CHECK(uart_driver_install(UART_NUM_0, 2048, 0, 0, nullptr, 0));
  ESP_ERROR_CHECK(esp_task_wdt_add(nullptr));
  
  // Board configuration from Kconfig
  motolink::BoardConfig board_cfg = {};
  board_cfg.gnss_rx = CONFIG_MOTOLINK_GNSS_RX;
  board_cfg.gnss_baud = CONFIG_MOTOLINK_GNSS_BAUD;
  board_cfg.imu_spi_host = CONFIG_MOTOLINK_IMU_SPI_HOST;
  board_cfg.imu_cs = CONFIG_MOTOLINK_IMU_CS;
  board_cfg.imu_int = CONFIG_MOTOLINK_IMU_INT;
  board_cfg.ble_name = CONFIG_MOTOLINK_BLE_DEVICE_NAME;
  board_cfg.storage_slot = CONFIG_MOTOLINK_STORAGE_SLOT;
  board_cfg.can_tx = CONFIG_MOTOLINK_CAN_TX;
  board_cfg.can_rx = CONFIG_MOTOLINK_CAN_RX;
  board_cfg.can_bitrate = CONFIG_MOTOLINK_CAN_BITRATE;
  board_cfg.led_gpio = CONFIG_MOTOLINK_LED_GPIO;
  board_cfg.led_active_high = CONFIG_MOTOLINK_LED_ACTIVE_HIGH;
  board_cfg.btn_gpio = CONFIG_MOTOLINK_BTN_GPIO;
  board_cfg.btn_active_low = CONFIG_MOTOLINK_BTN_ACTIVE_LOW;
  
  // Initialize board peripherals
  uint32_t modules = motolink::board_init(board_cfg, boot_time,
                                          &gnss, &imu, &ble, &storage, &can,
                                          &status_led, &service_btn);
  
  // Track which modules are online
  bool gnss_online = (modules & motolink::MOD_GNSS) != 0;
  bool imu_online = (modules & motolink::MOD_IMU) != 0;
  bool ble_online = (modules & motolink::MOD_BLE) != 0;
  bool storage_online = (modules & motolink::MOD_STORAGE) != 0;
  bool can_online = (modules & motolink::MOD_CAN) != 0;
  
  if (!gnss_online && CONFIG_MOTOLINK_GNSS_ENABLED) {
    core.fail(100);
    ESP_LOGE(tag, "GNSS init failed");
  }
  
  core.initialization_complete();
  ESP_LOGI(tag, "MotoLink 0.1.0; modules: 0x%02lX", (unsigned long)modules);
  ESP_LOGI(tag, "Commands: PING STATUS GNSS IMU VERSION LED STORAGE_INFO CAN_FILTER");
  
  char line[96] = {};
  std::size_t used = 0;
  bool discard = false;
  std::uint8_t bytes[128];
  uint32_t last_module_update = 0;
  
  while (true) {
    const uint32_t now = now_ms();
    core.tick(now);
    
    // Board update (LED, button, BLE, CAN, storage sync)
    motolink::board_update(now, &gnss, &imu, &ble, &storage, &can,
                           &status_led, &service_btn);
    
    // Handle button events
    auto evt = service_btn.poll(now);
    if (evt == motolink::ButtonEvent::short_press) {
      status_led.set_pattern(motolink::LedPattern::triple_blink);
      ESP_LOGI(tag, "Service button: short press");
    } else if (evt == motolink::ButtonEvent::long_press) {
      ESP_LOGI(tag, "Service button: long press - restart");
      esp_restart();
    } else if (evt == motolink::ButtonEvent::very_long_press) {
      ESP_LOGI(tag, "Service button: very long press - factory reset");
    } else if (evt == motolink::ButtonEvent::double_click) {
      ESP_LOGI(tag, "Service button: double click");
    }
    
    // Console input
    const int received = uart_read_bytes(UART_NUM_0, bytes, sizeof(bytes), 0);
    for (int i = 0; i < received; ++i) {
      const char c = static_cast<char>(bytes[i]);
      if (c == '\r' || c == '\n') {
        if (discard) std::printf("{\"error\":\"invalid_line\"}\n");
        else if (used) { line[used] = '\0'; command(line, now); }
        used = 0; discard = false;
      } else if (!discard) {
        if (c < 32 || c > 126 || used >= sizeof(line) - 1) discard = true;
        else line[used++] = c;
      }
    }
    
    // GNSS UART
    if (gnss_online) {
      const int count = uart_read_bytes(UART_NUM_1, bytes, sizeof(bytes), 0);
      for (int i = 0; i < count; ++i) gnss.feed(static_cast<char>(bytes[i]), now);
    }
    
    // Periodic module updates
    if (now - last_module_update >= 100) {
      if (imu_online) imu.read(now);
      // BLE and CAN updated in board_update
      last_module_update = now;
    }
    
    // Update LED pattern based on system state
    const auto nav = gnss.navigation(now);
    if (core.status().state == motolink::State::fault) {
      status_led.set_pattern(motolink::LedPattern::fast_blink);
    } else if (core.status().state == motolink::State::ready) {
      if (nav.valid && ble_online) {
        status_led.set_pattern(motolink::LedPattern::triple_blink);
      } else if (nav.valid) {
        status_led.set_pattern(motolink::LedPattern::heartbeat);
      } else {
        status_led.set_pattern(motolink::LedPattern::breathing);
      }
    }
    
    ESP_ERROR_CHECK(esp_task_wdt_reset());
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}