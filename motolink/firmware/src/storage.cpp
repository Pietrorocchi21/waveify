#include "motolink/storage.hpp"
#include "esp_vfs_fat.h"
#include "driver/sdmmc_host.h"
#include "sdmmc_cmd.h"
#include "esp_log.h"
#include "esp_partition.h"
#include <cstring>
#include <cstdio>
#include <sys/stat.h>

namespace motolink {

static constexpr char tag[] = "storage";
static sdmmc_card_t* card = nullptr;
static bool sd_card_mounted = false;

static uint32_t crc32_table[256];
static bool crc32_table_init = false;

static void init_crc32_table() {
  if (crc32_table_init) return;
  for (uint32_t i = 0; i < 256; ++i) {
    uint32_t c = i;
    for (int j = 0; j < 8; ++j) {
      c = (c & 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    crc32_table[i] = c;
  }
  crc32_table_init = true;
}

static uint32_t crc32_update(uint32_t crc, const uint8_t* data, size_t len) {
  init_crc32_table();
  crc = ~crc;
  for (size_t i = 0; i < len; ++i) {
    crc = crc32_table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
  }
  return ~crc;
}

bool Storage::begin(uint32_t now_ms) {
  state_ = StorageState::unmounted;
  initialized_ = false;
  card_present_ = false;
  gnss_log_open_ = false;
  imu_log_open_ = false;
  events_log_open_ = false;
  gnss_entries_ = 0;
  imu_entries_ = 0;
  event_entries_ = 0;
  buffer_used_ = 0;

  sdmmc_host_t host = SDMMC_HOST_DEFAULT();
  host.slot = 0;

  sdmmc_slot_config_t slot_config = SDMMC_SLOT_CONFIG_DEFAULT();
  slot_config.width = 1;
  slot_config.clk = GPIO_NUM_14;
  slot_config.cmd = GPIO_NUM_13;
  slot_config.d0 = GPIO_NUM_12;
  slot_config.d1 = GPIO_NUM_NC;
  slot_config.d2 = GPIO_NUM_NC;
  slot_config.d3 = GPIO_NUM_NC;
  slot_config.card_detect = GPIO_NUM_NC;
  slot_config.wp = GPIO_NUM_NC;

  esp_vfs_fat_mount_config_t mount_config = {};
  mount_config.format_if_mount_failed = false;
  mount_config.max_files = 5;
  mount_config.allocation_unit_size = 16 * 1024;

  esp_err_t err = esp_vfs_fat_sdmmc_mount("/sdcard", &host, &slot_config, &mount_config, &card);
  if (err != ESP_OK) {
    ESP_LOGE(tag, "Failed to mount SD card: %s", esp_err_to_name(err));
    state_ = StorageState::error;
    return false;
  }

  card_present_ = true;
  state_ = StorageState::mounted;
  initialized_ = true;

  mkdir("/sdcard/logs", 0755);
  mkdir("/sdcard/config", 0755);
  mkdir("/sdcard/firmware", 0755);

  ESP_LOGI(tag, "SD card mounted, size: %llu MB", (unsigned long long)card->csd.capacity * 512 / (1024 * 1024));
  return true;
}

void Storage::end() {
  if (!initialized_) return;
  close_log(LogType::gnss);
  close_log(LogType::imu);
  close_log(LogType::events);
  esp_vfs_fat_sdcard_unmount("/sdcard", card);
  initialized_ = false;
  card_present_ = false;
  state_ = StorageState::unmounted;
}

bool Storage::create_log(LogType type, uint32_t now_ms) {
  if (state_ != StorageState::mounted) return false;

  char filename[64];
  const char* base = "/sdcard/logs";
  const char* ext = ".bin";

  switch (type) {
    case LogType::gnss:
      snprintf(filename, sizeof(filename), "%s/gnss_%lu%s", base, now_ms, ext);
      break;
    case LogType::imu:
      snprintf(filename, sizeof(filename), "%s/imu_%lu%s", base, now_ms, ext);
      break;
    case LogType::events:
      snprintf(filename, sizeof(filename), "%s/evt_%lu%s", base, now_ms, ext);
      break;
    default:
      return false;
  }

  FILE* f = fopen(filename, "wb");
  if (!f) return false;

  LogHeader header = {};
  header.magic = 0x4D4F544C;
  header.version = 1;
  header.entry_size = (type == LogType::gnss) ? sizeof(GnssEntry) : 
                      (type == LogType::imu) ? sizeof(ImuEntry) : sizeof(EventEntry);
  header.entry_count = 0;
  header.start_time = now_ms;
  header.end_time = 0;
  header.crc32 = 0;

  fwrite(&header, sizeof(header), 1, f);
  fclose(f);

  switch (type) {
    case LogType::gnss: gnss_log_open_ = true; gnss_entries_ = 0; break;
    case LogType::imu: imu_log_open_ = true; imu_entries_ = 0; break;
    case LogType::events: events_log_open_ = true; event_entries_ = 0; break;
    default: return false;
  }
  return true;
}

bool Storage::close_log(LogType type) {
  if (state_ != StorageState::mounted) return false;
  switch (type) {
    case LogType::gnss: gnss_log_open_ = false; break;
    case LogType::imu: imu_log_open_ = false; break;
    case LogType::events: events_log_open_ = false; break;
    default: return false;
  }
  return true;
}

bool Storage::write_gnss(const GnssEntry& entry) {
  if (!gnss_log_open_) return false;
  gnss_entries_++;
  return true;
}

bool Storage::write_imu(const ImuEntry& entry) {
  if (!imu_log_open_) return false;
  imu_entries_++;
  return true;
}

bool Storage::write_event(uint16_t code, uint16_t data, uint32_t extra) {
  if (!events_log_open_) return false;
  event_entries_++;
  return true;
}

bool Storage::sync() {
  if (state_ != StorageState::mounted) return false;
  return true;
}

uint32_t Storage::free_bytes() const {
  if (!card) return 0;
  return static_cast<uint32_t>(card->csd.capacity * 512);
}

uint32_t Storage::total_bytes() const {
  if (!card) return 0;
  return static_cast<uint32_t>(card->csd.capacity * 512);
}

bool Storage::is_card_present() const { return card_present_; }

bool Storage::list_files() { return true; }

}  // namespace motolink
