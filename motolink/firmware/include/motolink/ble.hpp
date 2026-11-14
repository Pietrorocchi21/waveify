#pragma once
#include <cstdint>
#include <cstring>

namespace motolink {

// BLE service UUID: 128-bit custom UUID for MotoLink
// 00000000-0000-0000-0000-000000000000 placeholder
constexpr uint8_t SERVICE_UUID[16] = {
  0x4D, 0x4F, 0x54, 0x4F, 0x4C, 0x49, 0x4E, 0x4B,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

// Characteristic UUIDs
constexpr uint8_t CHAR_NAV_UUID[16] = {  // Navigation data (notify)
  0x4E, 0x41, 0x56, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
};
constexpr uint8_t CHAR_IMU_UUID[16] = {  // IMU data (notify)
  0x49, 0x4D, 0x55, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
};
constexpr uint8_t CHAR_CMD_UUID[16] = {  // Commands (write)
  0x43, 0x4D, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03
};
constexpr uint8_t CHAR_CFG_UUID[16] = {  // Configuration (read/write)
  0x43, 0x46, 0x47, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04
};
constexpr uint8_t CHAR_INFO_UUID[16] = {  // Device info (read)
  0x49, 0x4E, 0x46, 0x4F, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05
};

enum class BleState : uint8_t {
  off,
  advertising,
  connected,
  pairing
};

struct NavPayload {
  uint32_t timestamp_ms;
  int32_t latitude_e7;    // degrees * 1e7
  int32_t longitude_e7;   // degrees * 1e7
  int16_t speed_kmh_x10;  // km/h * 10
  uint8_t fix_quality;    // 0=none, 1=GPS, 2=DGPS, etc.
  uint8_t satellites;
} __attribute__((packed));

struct ImuPayload {
  uint32_t timestamp_ms;
  int16_t ax, ay, az;     // mg (milli-g)
  int16_t gx, gy, gz;     // mdps (milli-degrees per second)
  int16_t temperature;    // 0.01 deg C
} __attribute__((packed));

enum class CmdCode : uint8_t {
  ping = 0x01,
  get_status = 0x02,
  restart = 0x03,
  factory_reset = 0x04,
  start_logging = 0x10,
  stop_logging = 0x11,
  calibrate_imu = 0x20,
  set_gnss_rate = 0x30,
};

struct CommandFrame {
  uint8_t code;
  uint8_t payload_len;
  uint8_t payload[16];
  uint8_t crc8;
} __attribute__((packed));

struct ConfigFrame {
  uint32_t gnss_update_ms;
  uint32_t imu_update_ms;
  uint32_t ble_adv_interval_ms;
  uint8_t  log_level;
  uint8_t  reserved[3];
} __attribute__((packed));

struct InfoFrame {
  char firmware_version[16];
  char hardware_version[16];
  uint8_t mac[6];
  uint32_t uptime_seconds;
  uint32_t free_heap;
} __attribute__((packed));

class Ble {
 public:
  enum class Mode { off, peripheral };
  
  bool begin(uint32_t now_ms, const char* device_name = "MotoLink");
  void end();
  Mode mode() const { return mode_; }
  BleState state() const { return state_; }
  
  // Notify functions (only when connected and subscribed)
  bool notify_nav(const NavPayload& payload);
  bool notify_imu(const ImuPayload& payload);
  
  // Configuration
  bool set_config(const ConfigFrame& cfg);
  bool get_config(ConfigFrame& cfg) const;
  
  // Device info
  void set_info(const InfoFrame& info);
  
  // Process BLE events (call from main loop)
  void process(uint32_t now_ms);
  
  // Pairing/bonding
  bool is_bonded() const;
  void clear_bonds();
  
 private:
  Mode mode_ = Mode::off;
  BleState state_ = BleState::off;
  bool initialized_ = false;
  bool connected_ = false;
  bool nav_subscribed_ = false;
  bool imu_subscribed_ = false;
  uint32_t adv_start_ms_ = 0;
  uint32_t last_adv_ms_ = 0;
  uint16_t conn_handle_ = 0xFFFF;
  
  ConfigFrame config_;
  InfoFrame info_;
  
  // CRC8 for command frames
  static uint8_t crc8(const uint8_t* data, size_t len);
};

}  // namespace motolink
