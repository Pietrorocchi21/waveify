#include "motolink/ble.hpp"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_device.h"
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include <cstring>

namespace motolink {

static constexpr char tag[] = "ble";
static uint16_t service_handle = 0;
static uint16_t nav_char_handle = 0;
static uint16_t imu_char_handle = 0;
static uint16_t cmd_char_handle = 0;
static uint16_t cfg_char_handle = 0;
static uint16_t info_char_handle = 0;
static esp_gatt_if_t gatts_if_global = ESP_GATT_IF_NONE;
static uint16_t conn_id_global = 0xFFFF;
static bool is_connected = false;
static bool is_nav_notify_enabled = false;
static bool is_imu_notify_enabled = false;

uint8_t Ble::crc8(const uint8_t* data, size_t len) {
  uint8_t crc = 0;
  for (size_t i = 0; i < len; ++i) {
    crc ^= data[i];
    for (int j = 0; j < 8; ++j) {
      crc = (crc & 0x80) ? (crc << 1) ^ 0x07 : (crc << 1);
    }
  }
  return crc;
}

bool Ble::begin(uint32_t now_ms, const char* device_name) {
  mode_ = Mode::off;
  state_ = BleState::off;
  initialized_ = false;
  connected_ = false;
  nav_subscribed_ = false;
  imu_subscribed_ = false;
  conn_handle_ = 0xFFFF;

  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ret = nvs_flash_init();
  }
  if (ret != ESP_OK) return false;

  ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));
  esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
  ret = esp_bt_controller_init(&bt_cfg);
  if (ret != ESP_OK) return false;
  ret = esp_bt_controller_enable(ESP_BT_MODE_BLE);
  if (ret != ESP_OK) return false;
  ret = esp_bluedroid_init();
  if (ret != ESP_OK) return false;
  ret = esp_bluedroid_enable();
  if (ret != ESP_OK) return false;

  config_.gnss_update_ms = 1000;
  config_.imu_update_ms = 100;
  config_.ble_adv_interval_ms = 500;
  config_.log_level = 2;
  std::memset(config_.reserved, 0, sizeof(config_.reserved));
  std::strncpy(info_.firmware_version, "0.1.0", sizeof(info_.firmware_version) - 1);
  std::strncpy(info_.hardware_version, "proto1", sizeof(info_.hardware_version) - 1);

  mode_ = Mode::peripheral;
  state_ = BleState::advertising;
  adv_start_ms_ = now_ms;
  last_adv_ms_ = now_ms;
  initialized_ = true;

  return true;
}

void Ble::end() {
  if (!initialized_) return;
  initialized_ = false;
  mode_ = Mode::off;
  state_ = BleState::off;
  connected_ = false;
}

bool Ble::notify_nav(const NavPayload& payload) { return connected_ && nav_subscribed_; }
bool Ble::notify_imu(const ImuPayload& payload) { return connected_ && imu_subscribed_; }
bool Ble::set_config(const ConfigFrame& cfg) { config_ = cfg; return true; }
bool Ble::get_config(ConfigFrame& cfg) const { cfg = config_; return true; }
void Ble::set_info(const InfoFrame& info) { info_ = info; }
void Ble::process(uint32_t now_ms) { if (initialized_) connected_ = is_connected; }
bool Ble::is_bonded() const { return false; }
void Ble::clear_bonds() { }

}  // namespace motolink