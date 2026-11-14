#pragma once
#include <cstdint>
#include "sdkconfig.h"
#include "motolink/imu.hpp"
#include "motolink/ble.hpp"
#include "motolink/storage.hpp"
#include "motolink/can.hpp"
#include "motolink/status.hpp"
#include "motolink/motocan.hpp"

namespace motolink {

// Board-specific pin assignments from Kconfig
// These are defaults for ESP32-S3-DevKitC-1; override in Kconfig for custom PCB

// GNSS UART
#ifndef CONFIG_MOTOLINK_GNSS_ENABLED
#define CONFIG_MOTOLINK_GNSS_ENABLED 0
#endif
#ifndef CONFIG_MOTOLINK_GNSS_RX
#define CONFIG_MOTOLINK_GNSS_RX 4
#endif
#ifndef CONFIG_MOTOLINK_GNSS_BAUD
#define CONFIG_MOTOLINK_GNSS_BAUD 9600
#endif

// IMU SPI
#ifndef CONFIG_MOTOLINK_IMU_ENABLED
#define CONFIG_MOTOLINK_IMU_ENABLED 0
#endif
#ifndef CONFIG_MOTOLINK_IMU_SPI_HOST
#define CONFIG_MOTOLINK_IMU_SPI_HOST 2
#endif
#ifndef CONFIG_MOTOLINK_IMU_CS
#define CONFIG_MOTOLINK_IMU_CS 5
#endif
#ifndef CONFIG_MOTOLINK_IMU_INT
#define CONFIG_MOTOLINK_IMU_INT 6
#endif

// BLE
#ifndef CONFIG_MOTOLINK_BLE_ENABLED
#define CONFIG_MOTOLINK_BLE_ENABLED 1
#endif
#ifndef CONFIG_MOTOLINK_BLE_DEVICE_NAME
#define CONFIG_MOTOLINK_BLE_DEVICE_NAME "MotoLink"
#endif

// Storage (SD card)
#ifndef CONFIG_MOTOLINK_STORAGE_ENABLED
#define CONFIG_MOTOLINK_STORAGE_ENABLED 0
#endif
#ifndef CONFIG_MOTOLINK_STORAGE_SLOT
#define CONFIG_MOTOLINK_STORAGE_SLOT 0
#endif

// CAN (TWAI) - DISABLED on Core, used only on MotoCAN Adapter
#ifndef CONFIG_MOTOLINK_CAN_ENABLED
#define CONFIG_MOTOLINK_CAN_ENABLED 0
#endif
#ifndef CONFIG_MOTOLINK_CAN_TX
#define CONFIG_MOTOLINK_CAN_TX 7
#endif
#ifndef CONFIG_MOTOLINK_CAN_RX
#define CONFIG_MOTOLINK_CAN_RX 8
#endif
#ifndef CONFIG_MOTOLINK_CAN_BITRATE
#define CONFIG_MOTOLINK_CAN_BITRATE 500000
#endif

// Status LED
#ifndef CONFIG_MOTOLINK_LED_GPIO
#define CONFIG_MOTOLINK_LED_GPIO 2
#endif
#ifndef CONFIG_MOTOLINK_LED_ACTIVE_HIGH
#define CONFIG_MOTOLINK_LED_ACTIVE_HIGH 0
#endif

// Service Button
#ifndef CONFIG_MOTOLINK_BTN_GPIO
#define CONFIG_MOTOLINK_BTN_GPIO 0
#endif
#ifndef CONFIG_MOTOLINK_BTN_ACTIVE_LOW
#define CONFIG_MOTOLINK_BTN_ACTIVE_LOW 1
#endif

// Power Monitor (ADC)
#ifndef CONFIG_MOTOLINK_POWER_MONITOR
#define CONFIG_MOTOLINK_POWER_MONITOR 0
#endif
#ifndef CONFIG_MOTOLINK_POWER_ADC_CHANNEL
#define CONFIG_MOTOLINK_POWER_ADC_CHANNEL 0
#endif

// BLE Client for MotoCAN Adapter
#ifndef CONFIG_MOTOLINK_BLE_CLIENT_ENABLED
#define CONFIG_MOTOLINK_BLE_CLIENT_ENABLED 1
#endif
#ifndef CONFIG_MOTOLINK_BLE_CLIENT_NAME
#define CONFIG_MOTOLINK_BLE_CLIENT_NAME "MotoCAN"
#endif

// Board initialization - call from app_main after core.begin()
struct BoardConfig {
  uint8_t gnss_rx = CONFIG_MOTOLINK_GNSS_RX;
  uint32_t gnss_baud = CONFIG_MOTOLINK_GNSS_BAUD;
  uint8_t imu_spi_host = CONFIG_MOTOLINK_IMU_SPI_HOST;
  uint8_t imu_cs = CONFIG_MOTOLINK_IMU_CS;
  uint8_t imu_int = CONFIG_MOTOLINK_IMU_INT;
  const char* ble_name = CONFIG_MOTOLINK_BLE_DEVICE_NAME;
  uint8_t storage_slot = CONFIG_MOTOLINK_STORAGE_SLOT;
  uint8_t can_tx = CONFIG_MOTOLINK_CAN_TX;
  uint8_t can_rx = CONFIG_MOTOLINK_CAN_RX;
  uint32_t can_bitrate = CONFIG_MOTOLINK_CAN_BITRATE;
  uint8_t led_gpio = CONFIG_MOTOLINK_LED_GPIO;
  bool led_active_high = CONFIG_MOTOLINK_LED_ACTIVE_HIGH;
  uint8_t btn_gpio = CONFIG_MOTOLINK_BTN_GPIO;
  bool btn_active_low = CONFIG_MOTOLINK_BTN_ACTIVE_LOW;
  uint8_t power_adc_channel = CONFIG_MOTOLINK_POWER_ADC_CHANNEL;
  const char* motocan_name_prefix = CONFIG_MOTOLINK_BLE_CLIENT_NAME;
};

// Initialize all enabled peripherals
// Returns bitmask of successfully initialized modules
enum ModuleMask : uint32_t {
  MOD_GNSS   = 1 << 0,
  MOD_IMU    = 1 << 1,
  MOD_BLE    = 1 << 2,
  MOD_STORAGE = 1 << 3,
  MOD_CAN    = 1 << 4,
  MOD_LED    = 1 << 5,
  MOD_BTN    = 1 << 6,
  MOD_POWER  = 1 << 7,
  MOD_MOTOCAN = 1 << 8,
};

uint32_t board_init(const BoardConfig& cfg, uint32_t now_ms,
                    Nmea* gnss, Imu* imu, Ble* ble, Storage* storage, Can* can,
                    MotoCanClient* motocan, PowerMonitor* power,
                    StatusLed* led, ServiceButton* btn);

// Deinitialize all modules
void board_deinit(Nmea* gnss, Imu* imu, Ble* ble, Storage* storage, Can* can,
                  MotoCanClient* motocan, PowerMonitor* power,
                  StatusLed* led, ServiceButton* btn);

// Update all modules (call periodically from main loop)
void board_update(uint32_t now_ms, Nmea* gnss, Imu* imu, Ble* ble,
                  Storage* storage, Can* can, MotoCanClient* motocan,
                  PowerMonitor* power, StatusLed* led, ServiceButton* btn);

}  // namespace motolink
