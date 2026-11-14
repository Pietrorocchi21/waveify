#pragma once
#include <cstdint>
#include <cstring>

namespace motolink {

// MotoCAN Adapter data structures
// Normalized data from brand-specific CAN adapter via BLE

enum class MotoBrand : uint8_t {
  unknown = 0,
  ducati = 1,
  bmw = 2,
  kawasaki = 3,
  yamaha = 4,
  honda = 5,
  aprilia = 6,
  ktm = 7
};

enum class MotoCanState : uint8_t {
  disconnected = 0,
  connecting = 1,
  connected = 2,
  data_ready = 3,
  error = 4
};

struct MotoData {
  bool valid = false;
  uint32_t timestamp_ms = 0;
  
  // Engine
  uint16_t rpm = 0;
  uint8_t engine_temp_c = 0;
  uint8_t oil_temp_c = 0;
  uint8_t oil_pressure_bar = 0;
  
  // Speed & Gear
  uint16_t speed_kmh = 0;
  uint8_t gear = 0;  // 0 = neutral
  
  // Battery & Voltage
  uint16_t battery_voltage_mv = 0;
  
  // ECU
  uint32_t odometer_km = 0;
  uint8_t fault_code_count = 0;
  uint16_t fault_codes[8] = {0};
  
  // Throttle & Brakes
  uint8_t throttle_position_percent = 0;
  bool front_brake_active = false;
  bool rear_brake_active = false;
  
  MotoBrand brand = MotoBrand::unknown;
} __attribute__((packed));

// BLE GATT Service UUID for MotoCAN Adapter
// Custom 128-bit UUID: 00000000-0000-1000-8000-00805F9B34FB base
constexpr uint8_t MOTOCAN_SERVICE_UUID[16] = {
  0x4D, 0x4F, 0x54, 0x4F, 0x43, 0x41, 0x4E, 0x00,
  0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80
};

// Characteristics
constexpr uint8_t MOTOCAN_DATA_UUID[16] = {  // Notify
  0x44, 0x41, 0x54, 0x41, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
};
constexpr uint8_t MOTOCAN_CMD_UUID[16] = {  // Write
  0x43, 0x4D, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
};
constexpr uint8_t MOTOCAN_INFO_UUID[16] = {  // Read
  0x49, 0x4E, 0x46, 0x4F, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03
};

enum class MotoCanCmd : uint8_t {
  request_data = 0x01,
  request_faults = 0x02,
  clear_faults = 0x03,
  get_brand_info = 0x04
};

struct MotoCanInfo {
  char brand_name[32] = {0};
  char firmware_version[16] = {0};
  uint16_t protocol_version = 1;
  uint8_t max_data_rate_hz = 10;
  uint8_t connection_pin = 0;
} __attribute__((packed));

class MotoCanClient {
 public:
  enum class Mode { off, scanning, connecting, connected };
  
  bool begin(uint32_t now_ms, const char* adapter_name_prefix = "MotoCAN");
  void end();
  Mode mode() const { return mode_; }
  MotoCanState state() const { return state_; }
  
  // Connection management
  bool start_scan(uint32_t now_ms);
  bool connect(const char* device_name);
  void disconnect();
  bool is_connected() const;
  
  // Data
  bool get_data(MotoData& data) const;
  bool update_data(const uint8_t* payload, size_t len, uint32_t now_ms);
  
  // Commands
  bool request_data();
  bool request_faults();
  bool clear_faults();
  bool get_info(MotoCanInfo& info);
  
  // Process BLE events
  void process(uint32_t now_ms);
  
 private:
  Mode mode_ = Mode::off;
  MotoCanState state_ = MotoCanState::disconnected;
  bool initialized_ = false;
  bool connected_ = false;
  
  uint32_t scan_start_ms_ = 0;
  uint32_t last_data_ms_ = 0;
  uint32_t connect_timeout_ms_ = 0;
  uint32_t last_conn_attempt_ms_ = 0;
  
  char adapter_name_[32] = {0};
  char connected_device_name_[32] = {0};
  
  MotoData data_;
  MotoCanInfo info_;
  
  uint16_t service_handle_ = 0;
  uint16_t data_char_handle_ = 0;
  uint16_t cmd_char_handle_ = 0;
  uint16_t info_char_handle_ = 0;
  
  uint16_t conn_id_ = 0xFFFF;
};

// Power monitoring via ADC
struct PowerMonitor {
  bool initialized = false;
  uint8_t adc_channel = 0;
  uint16_t vref_mv = 3300;
  uint16_t divider_ratio = 11;  // 10:1 divider for 12V
  
  void begin(uint8_t channel);
  uint16_t read_voltage_mv() const;
  float read_voltage_v() const;
  bool is_low_battery() const;
};

}  // namespace motolink
