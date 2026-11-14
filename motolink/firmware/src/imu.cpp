#include "motolink/imu.hpp"
#include "driver/spi_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <cmath>

namespace motolink {

static constexpr char tag[] = "imu";

// BMI270 registers
namespace reg {
constexpr uint8_t CHIP_ID       = 0x00;
constexpr uint8_t ERR_REG       = 0x02;
constexpr uint8_t STATUS        = 0x03;
constexpr uint8_t ACC_CONF      = 0x40;
constexpr uint8_t GYR_CONF      = 0x42;
constexpr uint8_t ACC_RANGE     = 0x41;
constexpr uint8_t GYR_RANGE     = 0x43;
constexpr uint8_t PWR_CONF      = 0x7C;
constexpr uint8_t PWR_CTRL      = 0x7D;
constexpr uint8_t CMD           = 0x7E;
constexpr uint8_t DATA_0        = 0x0A;  // accel x LSB
constexpr uint8_t DATA_1        = 0x0B;
constexpr uint8_t DATA_2        = 0x0C;  // accel y LSB
constexpr uint8_t DATA_3        = 0x0D;
constexpr uint8_t DATA_4        = 0x0E;  // accel z LSB
constexpr uint8_t DATA_5        = 0x0F;
constexpr uint8_t DATA_6        = 0x10;  // gyro x LSB
constexpr uint8_t DATA_7        = 0x11;
constexpr uint8_t DATA_8        = 0x12;  // gyro y LSB
constexpr uint8_t DATA_9        = 0x13;
constexpr uint8_t DATA_10       = 0x14;  // gyro z LSB
constexpr uint8_t DATA_11       = 0x15;
constexpr uint8_t TEMP_DATA     = 0x22;
constexpr uint8_t TEMP_DATA_MSB = 0x23;
constexpr uint8_t INT_MAP_DATA  = 0x58;
constexpr uint8_t INT1_IO_CTRL  = 0x56;
constexpr uint8_t INT2_IO_CTRL  = 0x57;
constexpr uint8_t IF_CONF       = 0x6B;
constexpr uint8_t NVM_CONF      = 0x70;
constexpr uint8_t OFFSET_0      = 0x71;  // Accel X offset
constexpr uint8_t OFFSET_1      = 0x72;
constexpr uint8_t OFFSET_2      = 0x73;  // Accel Y offset
constexpr uint8_t OFFSET_3      = 0x74;
constexpr uint8_t OFFSET_4      = 0x75;  // Accel Z offset
constexpr uint8_t OFFSET_5      = 0x76;
constexpr uint8_t OFFSET_6      = 0x77;  // Gyro X offset
constexpr uint8_t OFFSET_7      = 0x78;
constexpr uint8_t OFFSET_8      = 0x79;  // Gyro Y offset
constexpr uint8_t OFFSET_9      = 0x7A;
constexpr uint8_t OFFSET_10     = 0x7B;  // Gyro Z offset
constexpr uint8_t OFFSET_11     = 0x7C;
constexpr uint8_t CMD_START_FOC = 0x03;
constexpr uint8_t CMD_SOFT_RESET = 0xB6;
}

// SPI commands
constexpr uint8_t SPI_READ  = 0x80;
constexpr uint8_t SPI_WRITE = 0x00;

// Expected chip ID for BMI270
constexpr uint8_t BMI270_CHIP_ID = 0x24;

// SPI device handle
static spi_device_handle_t imu_spi_handle = nullptr;

static esp_err_t spi_write(uint8_t reg, uint8_t value) {
  if (!imu_spi_handle) return ESP_ERR_INVALID_STATE;
  spi_transaction_t trans = {};
  trans.flags = 0;
  trans.length = 16;  // 8 bits address + 8 bits data
  trans.tx_data[0] = SPI_WRITE | reg;
  trans.tx_data[1] = value;
  trans.flags |= SPI_TRANS_USE_TXDATA;
  return spi_device_polling_transmit(imu_spi_handle, &trans);
}

static esp_err_t spi_read(uint8_t reg, uint8_t* value) {
  if (!imu_spi_handle) return ESP_ERR_INVALID_STATE;
  spi_transaction_t trans = {};
  trans.flags = 0;
  trans.length = 16;
  trans.rxlength = 16;
  trans.tx_data[0] = SPI_READ | reg;
  trans.tx_data[1] = 0x00;
  trans.flags |= SPI_TRANS_USE_TXDATA | SPI_TRANS_USE_RXDATA;
  esp_err_t err = spi_device_polling_transmit(imu_spi_handle, &trans);
  if (err == ESP_OK) *value = trans.rx_data[1];
  return err;
}

static esp_err_t spi_read16(uint8_t reg, int16_t* value) {
  uint8_t lsb, msb;
  esp_err_t err = spi_read(reg, &lsb);
  if (err != ESP_OK) return err;
  err = spi_read(reg + 1, &msb);
  if (err != ESP_OK) return err;
  *value = static_cast<int16_t>((msb << 8) | lsb);
  return ESP_OK;
}

static esp_err_t spi_burst_read(uint8_t reg, uint8_t* buffer, size_t len) {
  if (!imu_spi_handle) return ESP_ERR_INVALID_STATE;
  spi_transaction_t trans = {};
  trans.length = (len + 1) * 8;
  trans.rxlength = (len + 1) * 8;
  trans.tx_buffer = new uint8_t[len + 1];
  trans.rx_buffer = new uint8_t[len + 1];
  static_cast<uint8_t*>(trans.tx_buffer)[0] = SPI_READ | reg;
  esp_err_t err = spi_device_polling_transmit(imu_spi_handle, &trans);
  if (err == ESP_OK) {
    memcpy(buffer, static_cast<uint8_t*>(trans.rx_buffer) + 1, len);
  }
  delete[] trans.tx_buffer;
  delete[] trans.rx_buffer;
  return err;
}

bool Imu::begin(uint32_t now_ms) {
  mode_ = Mode::off;
  initialized_ = false;
  ax_off_ = ay_off_ = az_off_ = 0;
  gx_off_ = gy_off_ = gz_off_ = 0;

  // Note: SPI bus initialization is done in board.cpp
  // We assume the SPI bus is already initialized and just add the device
  
  // For now, check if SPI handle exists (set by board_init)
  if (!imu_spi_handle) {
    ESP_LOGE(tag, "SPI handle not initialized - call board_init first");
    return false;
  }

  // Soft reset
  esp_err_t err = spi_write(reg::CMD, reg::CMD_SOFT_RESET);
  if (err != ESP_OK) return false;
  vTaskDelay(pdMS_TO_TICKS(10));

  // Check chip ID
  uint8_t chip_id = 0;
  err = spi_read(reg::CHIP_ID, &chip_id);
  if (err != ESP_OK || chip_id != BMI270_CHIP_ID) {
    ESP_LOGE(tag, "Chip ID mismatch: 0x%02X (expected 0x%02X)", chip_id, BMI270_CHIP_ID);
    return false;
  }
  ESP_LOGI(tag, "BMI270 detected (chip ID: 0x%02X)", chip_id);

  // Power up: disable advanced power saving
  err = spi_write(reg::PWR_CONF, 0x00);
  if (err != ESP_OK) return false;

  // Enable accel + gyro + temp in normal mode
  err = spi_write(reg::PWR_CTRL, 0x0F);
  if (err != ESP_OK) return false;
  vTaskDelay(pdMS_TO_TICKS(10));

  // Configure accel: +/-4g, ODR 100Hz, normal mode (OSR2)
  // ACC_CONF: [7:4] ODR=0xA (100Hz), [3:1] OSR=0x4 (OSR2), [0] filter_perf=1
  err = spi_write(reg::ACC_RANGE, 0x01);  // +/-4g
  if (err != ESP_OK) return false;
  err = spi_write(reg::ACC_CONF, 0xA8);
  if (err != ESP_OK) return false;

  // Configure gyro: +/-2000 dps, ODR 100Hz, normal mode
  // GYR_CONF: [7:4] ODR=0xA (100Hz), [3:1] OSR=0x4 (OSR2), [0] filter=1
  // GYR_RANGE: 0x00 = +/-2000 dps
  err = spi_write(reg::GYR_RANGE, 0x00);
  if (err != ESP_OK) return false;
  err = spi_write(reg::GYR_CONF, 0xA9);
  if (err != ESP_OK) return false;

  // Enable data ready interrupt on INT1 (push-pull, active high)
  err = spi_write(reg::INT_MAP_DATA, 0x04);
  if (err != ESP_OK) return false;
  err = spi_write(reg::INT1_IO_CTRL, 0x02);
  if (err != ESP_OK) return false;

  // Fast Offset Compensation calibration
  ESP_LOGI(tag, "Starting FOC calibration...");
  err = spi_write(reg::CMD, reg::CMD_START_FOC);
  if (err != ESP_OK) return false;
  vTaskDelay(pdMS_TO_TICKS(250));

  // Read back offsets
  spi_read16(reg::OFFSET_0, &ax_off_);
  spi_read16(reg::OFFSET_2, &ay_off_);
  spi_read16(reg::OFFSET_4, &az_off_);
  spi_read16(reg::OFFSET_6, &gx_off_);
  spi_read16(reg::OFFSET_8, &gy_off_);
  spi_read16(reg::OFFSET_10, &gz_off_);

  ESP_LOGI(tag, "Offsets: ax=%d ay=%d az=%d gx=%d gy=%d gz=%d",
           ax_off_, ay_off_, az_off_, gx_off_, gy_off_, gz_off_);

  initialized_ = true;
  mode_ = Mode::active;
  return true;
}

void Imu::end() {
  if (!initialized_) return;
  spi_write(reg::PWR_CTRL, 0x00);  // Suspend all sensors
  spi_write(reg::PWR_CONF, 0x03);  // Deep sleep
  initialized_ = false;
  mode_ = Mode::off;
}

ImuSample Imu::read(uint32_t now_ms) {
  ImuSample sample;
  sample.timestamp_ms = now_ms;

  if (!initialized_) {
    sample.valid = false;
    return sample;
  }

  // Burst read 12 bytes from DATA_0 (accel x,y,z + gyro x,y,z)
  uint8_t buffer[12];
  esp_err_t err = spi_burst_read(reg::DATA_0, buffer, 12);
  if (err != ESP_OK) {
    sample.valid = false;
    return sample;
  }

  int16_t raw_ax = static_cast<int16_t>((buffer[1] << 8) | buffer[0]);
  int16_t raw_ay = static_cast<int16_t>((buffer[3] << 8) | buffer[2]);
  int16_t raw_az = static_cast<int16_t>((buffer[5] << 8) | buffer[4]);
  int16_t raw_gx = static_cast<int16_t>((buffer[7] << 8) | buffer[6]);
  int16_t raw_gy = static_cast<int16_t>((buffer[9] << 8) | buffer[8]);
  int16_t raw_gz = static_cast<int16_t>((buffer[11] << 8) | buffer[10]);

  // Apply offsets
  sample.ax = raw_ax - ax_off_;
  sample.ay = raw_ay - ay_off_;
  sample.az = raw_az - az_off_;
  sample.gx = raw_gx - gx_off_;
  sample.gy = raw_gy - gy_off_;
  sample.gz = raw_gz - gz_off_;

  // Temperature (0.5 C/LSB, 23C at 0)
  int16_t raw_temp = 0;
  spi_read16(reg::TEMP_DATA, &raw_temp);
  sample.temperature = raw_temp;

  sample.valid = true;
  return sample;
}

bool Imu::self_test() const {
  if (!initialized_) return false;
  // Self-test: set self-test bit, read data, verify deflection, clear bit
  // This is a simplified check - full self-test requires specific sequence
  uint8_t status = 0;
  spi_read(reg::STATUS, &status);
  return (status & 0x10) != 0;  // Data ready bit
}

// Called from board_init to set the SPI handle
void imu_set_spi_handle(spi_device_handle_t handle) {
  imu_spi_handle = handle;
}

}  // namespace motolink
