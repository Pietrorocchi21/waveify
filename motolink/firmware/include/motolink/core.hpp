#pragma once

#include <cstdint>

namespace motolink {

enum class State : std::uint8_t { booting, ready, fault };
enum class Command : std::uint8_t { ping, get_status, unknown };

struct Status {
  State state;
  std::uint16_t fault_code;
  std::uint32_t uptime_ms;
};

struct Reply {
  bool accepted;
  Status status;
};

// The board adapter owns the clock, peripheral initialization and transport.
// This core performs no GPIO writes and allocates no dynamic memory.
class Core {
 public:
  void begin(std::uint32_t now_ms);
  void initialization_complete();
  void fail(std::uint16_t code);
  void tick(std::uint32_t now_ms);
  Status status() const;
  Reply handle(Command command) const;

 private:
  State state_ = State::booting;
  std::uint16_t fault_code_ = 0;
  std::uint32_t started_ms_ = 0;
  std::uint32_t uptime_ms_ = 0;
};

}  // namespace motolink
