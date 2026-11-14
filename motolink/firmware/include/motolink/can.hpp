#pragma once
#include <cstdint>
#include <cstddef>

namespace motolink {

enum class CanState : uint8_t {
  uninitialized,
  stopped,
  running,
  bus_off,
  error
};

enum class CanFormat : uint8_t {
  standard = 0,  // 11-bit ID
  extended = 1   // 29-bit ID
};

struct CanFrame {
  uint32_t id;
  uint8_t dlc;           // 0-8 (CAN) or 0-64 (CAN FD)
  uint8_t data[8];       // Up to 8 bytes for classic CAN
  CanFormat format;
  bool rtr;              // Remote transmission request
  uint32_t timestamp_ms; // RX timestamp
} __attribute__((packed));

struct CanFilter {
  uint32_t id;
  uint32_t mask;
  CanFormat format;
  bool enabled;
};

class Can {
 public:
  enum class Mode { off, listen_only, normal };
  
  bool begin(uint32_t now_ms, Mode mode = Mode::listen_only, uint32_t bitrate = 500000);
  void end();
  Mode mode() const { return mode_; }
  CanState state() const { return state_; }
  
  // Receive
  bool read(CanFrame& frame, uint32_t timeout_ms = 0);
  size_t available() const;
  
  // Transmit (only in normal mode)
  bool write(const CanFrame& frame, uint32_t timeout_ms = 100);
  
  // Filters (for listen-only mode, reduce CPU load)
  bool set_filter(uint8_t index, const CanFilter& filter);
  bool clear_filter(uint8_t index);
  
  // Statistics
  uint32_t rx_count() const { return rx_count_; }
  uint32_t tx_count() const { return tx_count_; }
  uint32_t rx_errors() const { return rx_errors_; }
  uint32_t tx_errors() const { return tx_errors_; }
  uint32_t bus_off_count() const { return bus_off_count_; }
  
  // Process (call from main loop for non-blocking operation)
  void process(uint32_t now_ms);
  
 private:
  Mode mode_ = Mode::off;
  CanState state_ = CanState::uninitialized;
  bool initialized_ = false;
  
  // RX queue (ring buffer)
  static constexpr size_t RX_QUEUE_SIZE = 64;
  CanFrame rx_queue_[RX_QUEUE_SIZE];
  size_t rx_head_ = 0;
  size_t rx_tail_ = 0;
  
  // Statistics
  uint32_t rx_count_ = 0;
  uint32_t tx_count_ = 0;
  uint32_t rx_errors_ = 0;
  uint32_t tx_errors_ = 0;
  uint32_t bus_off_count_ = 0;
  
  // TWAI timing configuration
  uint32_t bitrate_ = 500000;
};

}  // namespace motolink
