#include "motolink/core.hpp"

namespace motolink {

void Core::begin(std::uint32_t now_ms) {
  state_ = State::booting;
  fault_code_ = 0;
  started_ms_ = now_ms;
  uptime_ms_ = 0;
}

void Core::initialization_complete() {
  if (state_ == State::booting) state_ = State::ready;
}

void Core::fail(std::uint16_t code) {
  // Preserve the first fault until an explicit restart.
  if (state_ == State::fault) return;
  fault_code_ = code == 0 ? 1 : code;
  state_ = State::fault;
}

void Core::tick(std::uint32_t now_ms) {
  // Unsigned subtraction handles one wrap of the board's 32-bit clock.
  uptime_ms_ = now_ms - started_ms_;
}

Status Core::status() const {
  return {state_, fault_code_, uptime_ms_};
}

Reply Core::handle(Command command) const {
  return {command == Command::ping || command == Command::get_status, status()};
}

}  // namespace motolink
