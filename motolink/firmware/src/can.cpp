#include "motolink/can.hpp"
#include "driver/twai.h"
#include "esp_log.h"
#include <cstring>

namespace motolink {

static constexpr char tag[] = "can";

bool Can::begin(uint32_t now_ms, Mode mode, uint32_t bitrate) {
  mode_ = mode;
  bitrate_ = bitrate;
  state_ = CanState::uninitialized;
  initialized_ = false;
  rx_head_ = 0;
  rx_tail_ = 0;
  rx_count_ = 0;
  tx_count_ = 0;
  rx_errors_ = 0;
  tx_errors_ = 0;
  bus_off_count_ = 0;

  twai_general_config_t g_config = TWAI_GENERAL_CONFIG_DEFAULT(GPIO_NUM_7, GPIO_NUM_8, TWAI_MODE_LISTEN_ONLY);
  twai_timing_config_t t_config;
  
  if (bitrate == 500000) {
    t_config = TWAI_TIMING_CONFIG_500KBITS();
  } else if (bitrate == 250000) {
    t_config = TWAI_TIMING_CONFIG_250KBITS();
  } else if (bitrate == 100000) {
    t_config = TWAI_TIMING_CONFIG_100KBITS();
  } else {
    // Calculate timing for custom bitrate
    t_config.brp = 80;
    t_config.tseg_1 = 15;
    t_config.tseg_2 = 4;
    t_config.sjw = 3;
  }

  twai_filter_config_t f_config = TWAI_FILTER_CONFIG_ACCEPT_ALL();

  esp_err_t err = twai_driver_install(&g_config, &t_config, &f_config);
  if (err != ESP_OK) {
    ESP_LOGE(tag, "TWAI driver install failed: %s", esp_err_to_name(err));
    state_ = CanState::error;
    return false;
  }

  err = twai_start();
  if (err != ESP_OK) {
    ESP_LOGE(tag, "TWAI start failed: %s", esp_err_to_name(err));
    twai_driver_uninstall();
    state_ = CanState::error;
    return false;
  }

  state_ = CanState::running;
  initialized_ = true;
  ESP_LOGI(tag, "TWAI initialized, bitrate %lu bps, mode %s", bitrate, mode == Mode::listen_only ? "listen_only" : "normal");
  return true;
}

void Can::end() {
  if (!initialized_) return;
  twai_stop();
  twai_driver_uninstall();
  initialized_ = false;
  state_ = CanState::uninitialized;
  mode_ = Mode::off;
}

bool Can::read(CanFrame& frame, uint32_t timeout_ms) {
  if (state_ != CanState::running) return false;

  if (rx_head_ == rx_tail_) {
    twai_message_t msg;
    esp_err_t err = twai_receive(&msg, pdMS_TO_TICKS(timeout_ms));
    if (err != ESP_OK) return false;

    frame.id = msg.identifier;
    frame.format = msg.extd ? CanFormat::extended : CanFormat::standard;
    frame.rtr = msg.rtr;
    frame.dlc = msg.data_length_code;
    memcpy(frame.data, msg.data, msg.data_length_code);
    frame.timestamp_ms = 0;  // Would need to track separately
    rx_count_++;

    return true;
  }

  frame = rx_queue_[rx_tail_];
  rx_tail_ = (rx_tail_ + 1) % RX_QUEUE_SIZE;
  return true;
}

size_t Can::available() const {
  if (rx_head_ >= rx_tail_) return rx_head_ - rx_tail_;
  return RX_QUEUE_SIZE - (rx_tail_ - rx_head_);
}

bool Can::write(const CanFrame& frame, uint32_t timeout_ms) {
  if (mode_ != Mode::normal || state_ != CanState::running) return false;

  twai_message_t msg = {};
  msg.identifier = frame.id;
  msg.extd = (frame.format == CanFormat::extended);
  msg.rtr = frame.rtr;
  msg.data_length_code = frame.dlc;
  memcpy(msg.data, frame.data, frame.dlc);

  esp_err_t err = twai_transmit(&msg, pdMS_TO_TICKS(timeout_ms));
  if (err == ESP_OK) tx_count_++;
  else tx_errors_++;
  return err == ESP_OK;
}

bool Can::set_filter(uint8_t index, const CanFilter& filter) {
  if (index >= 4) return false;
  // TWAI filter configuration would require driver restart
  ESP_LOGW(tag, "Filter set not implemented for index %d", index);
  return false;
}

bool Can::clear_filter(uint8_t index) {
  if (index >= 4) return false;
  return false;
}

void Can::process(uint32_t now_ms) {
  if (!initialized_ || state_ != CanState::running) return;

  twai_message_t msg;
  while (twai_receive(&msg, 0) == ESP_OK) {
    CanFrame frame;
    frame.id = msg.identifier;
    frame.format = msg.extd ? CanFormat::extended : CanFormat::standard;
    frame.rtr = msg.rtr;
    frame.dlc = msg.data_length_code;
    memcpy(frame.data, msg.data, msg.data_length_code);
    frame.timestamp_ms = 0;

    size_t next_head = (rx_head_ + 1) % RX_QUEUE_SIZE;
    if (next_head != rx_tail_) {
      rx_queue_[rx_head_] = frame;
      rx_head_ = next_head;
      rx_count_++;
    } else {
      rx_errors_++;
    }
  }

  twai_status_info_t status;
  twai_get_status_info(&status);
  if (status.state == TWAI_STATE_BUS_OFF) {
    state_ = CanState::bus_off;
    bus_off_count_++;
    ESP_LOGW(tag, "TWAI bus off, count %lu", bus_off_count_);
  } else if (status.state == TWAI_STATE_STOPPED) {
    state_ = CanState::stopped;
  }
}

}  // namespace motolink
