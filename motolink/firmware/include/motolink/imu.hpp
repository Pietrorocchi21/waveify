#pragma once
#include <cstdint>

namespace motolink {

struct ImuSample {
  bool valid = false;
  int16_t ax = 0, ay = 0, az = 0;
  int16_t gx = 0, gy = 0, gz = 0;
  int16_t temperature = 0;
  uint32_t timestamp_ms = 0;
};

class Imu {
 public:
  enum class Mode { off, active };
  
  bool begin(uint32_t now_ms);
  void end();
  Mode mode() const { return mode_; }
  ImuSample read(uint32_t now_ms);
  bool self_test() const;
  
 private:
  Mode mode_ = Mode::off;
  bool initialized_ = false;
  int16_t ax_off_ = 0, ay_off_ = 0, az_off_ = 0;
  int16_t gx_off_ = 0, gy_off_ = 0, gz_off_ = 0;
  bool calibrating_ = false;
  uint32_t calib_start_ = 0;
  int32_t calib_sum_ax_ = 0, calib_sum_ay_ = 0, calib_sum_az_ = 0;
  int32_t calib_sum_gx_ = 0, calib_sum_gy_ = 0, calib_sum_gz_ = 0;
  uint16_t calib_count_ = 0;
};

// Called from board_init to provide the SPI device handle
void imu_set_spi_handle(void* handle);

}  // namespace motolink
