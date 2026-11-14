#pragma once
#include <cstdint>
#include <cstddef>

namespace motolink {

enum class StorageState : uint8_t {
  unmounted,
  mounting,
  mounted,
  error
};

enum class LogType : uint8_t {
  gnss = 0x01,
  imu = 0x02,
  events = 0x03,
  can = 0x04
};

struct LogHeader {
  uint32_t magic;        // 0x4D4F544C "MOTL"
  uint16_t version;      // 1
  uint16_t entry_size;   // Size of each entry
  uint32_t entry_count;  // Number of entries
  uint32_t start_time;   // Unix timestamp
  uint32_t end_time;     // Unix timestamp
  uint32_t crc32;        // CRC32 of all entries
} __attribute__((packed));

struct GnssEntry {
  uint32_t timestamp_ms;
  int32_t latitude_e7;
  int32_t longitude_e7;
  int16_t speed_kmh_x10;
  int16_t heading_x10;
  int16_t altitude_m;
  uint8_t fix_quality;
  uint8_t satellites;
  uint8_t hdop_x10;
  uint8_t reserved;
} __attribute__((packed));

struct ImuEntry {
  uint32_t timestamp_ms;
  int16_t ax, ay, az;
  int16_t gx, gy, gz;
  int16_t temperature;
  uint8_t reserved[2];
} __attribute__((packed));

struct EventEntry {
  uint32_t timestamp_ms;
  uint16_t event_code;
  uint16_t event_data;
  uint32_t extra;
} __attribute__((packed));

// Event codes
constexpr uint16_t EVT_BOOT = 0x0001;
constexpr uint16_t EVT_SHUTDOWN = 0x0002;
constexpr uint16_t EVT_GNSS_FIX = 0x0010;
constexpr uint16_t EVT_GNSS_LOST = 0x0011;
constexpr uint16_t EVT_BLE_CONNECT = 0x0020;
constexpr uint16_t EVT_BLE_DISCONNECT = 0x0021;
constexpr uint16_t EVT_IMU_CALIBRATED = 0x0030;
constexpr uint16_t EVT_CAN_MSG = 0x0040;
constexpr uint16_t EVT_ERROR = 0xFFFF;

class Storage {
 public:
  bool begin(uint32_t now_ms);
  void end();
  StorageState state() const { return state_; }
  
  // File operations
  bool create_log(LogType type, uint32_t now_ms);
  bool close_log(LogType type);
  bool write_gnss(const GnssEntry& entry);
  bool write_imu(const ImuEntry& entry);
  bool write_event(uint16_t code, uint16_t data, uint32_t extra = 0);
  
  // Maintenance
  bool sync();
  uint32_t free_bytes() const;
  uint32_t total_bytes() const;
  bool is_card_present() const;
  
  // File system info
  bool list_files();
  
 private:
  StorageState state_ = StorageState::unmounted;
  bool initialized_ = false;
  bool card_present_ = false;
  
  // Current log file handles (one per type)
  // TODO: Replace with actual file handles when using FATFS/SD_MMC
  bool gnss_log_open_ = false;
  bool imu_log_open_ = false;
  bool events_log_open_ = false;
  
  uint32_t gnss_entries_ = 0;
  uint32_t imu_entries_ = 0;
  uint32_t event_entries_ = 0;
  
  // Buffer for batched writes
  static constexpr size_t WRITE_BUFFER_SIZE = 512;
  uint8_t write_buffer_[WRITE_BUFFER_SIZE];
  size_t buffer_used_ = 0;
};

}  // namespace motolink
