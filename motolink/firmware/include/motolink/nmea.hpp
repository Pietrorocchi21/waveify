#pragma once
#include <cstddef>
#include <cstdint>

namespace motolink {
struct Navigation {
  bool valid = false;
  double latitude = 0;
  double longitude = 0;
  double speed_kmh = 0;
  std::uint32_t updated_ms = 0;
};

// Bounded NMEA RMC receiver. Only checksum-verified RMC affects navigation.
class Nmea {
 public:
  void feed(char byte, std::uint32_t now_ms);
  Navigation navigation(std::uint32_t now_ms) const;
  std::uint32_t accepted() const { return accepted_; }
  std::uint32_t rejected() const { return rejected_; }
 private:
  void parse(std::uint32_t now_ms);
  char line_[128] = {};
  std::size_t length_ = 0;
  bool collecting_ = false;
  Navigation nav_;
  std::uint32_t accepted_ = 0;
  std::uint32_t rejected_ = 0;
};
}
