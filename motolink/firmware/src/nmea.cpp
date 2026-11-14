#include "motolink/nmea.hpp"
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace {
int hex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}
bool number(const char* s, double& result) {
  if (!*s) return false;
  // Reject whitespace, signed, exponent and non-decimal NMEA fields.
  bool dot = false;
  bool digit = false;
  for (const char* p = s; *p; ++p) {
    if (*p == '.' && !dot) { dot = true; continue; }
    if (*p < '0' || *p > '9') return false;
    digit = true;
  }
  if (!digit) return false;
  char* end = nullptr;
  result = std::strtod(s, &end);
  return *end == '\0' && std::isfinite(result);
}
bool coordinate(const char* s, const char* hemisphere, bool latitude,
                double& result) {
  const std::size_t digits = latitude ? 4 : 5;
  const char* dot = std::strchr(s, '.');
  if ((dot ? static_cast<std::size_t>(dot - s) : std::strlen(s)) != digits)
    return false;
  double raw;
  if (!number(s, raw) || std::strlen(hemisphere) != 1) return false;
  const double degrees = std::floor(raw / 100);
  const double minutes = raw - degrees * 100;
  const double limit = latitude ? 90 : 180;
  if (minutes >= 60 || degrees > limit || (degrees == limit && minutes != 0))
    return false;
  const char h = *hemisphere;
  if (latitude ? (h != 'N' && h != 'S') : (h != 'E' && h != 'W')) return false;
  result = degrees + minutes / 60;
  if (h == 'S' || h == 'W') result = -result;
  return true;
}
}

namespace motolink {
void Nmea::feed(char byte, std::uint32_t now_ms) {
  if (byte == '$') { collecting_ = true; length_ = 0; return; }
  if (!collecting_) return;
  if (byte == '\r') return;
  if (byte == '\n') {
    line_[length_] = '\0';
    collecting_ = false;
    parse(now_ms);
    return;
  }
  if (byte < 32 || byte > 126 || length_ >= sizeof(line_) - 1) {
    collecting_ = false;
    ++rejected_;
    return;
  }
  line_[length_++] = byte;
}

void Nmea::parse(std::uint32_t now_ms) {
  char* star = std::strchr(line_, '*');
  if (!star || std::strlen(star) != 3 || hex(star[1]) < 0 || hex(star[2]) < 0) {
    ++rejected_; return;
  }
  unsigned checksum = 0;
  for (char* p = line_; p != star; ++p) checksum ^= static_cast<unsigned char>(*p);
  if (checksum != static_cast<unsigned>(hex(star[1]) * 16 + hex(star[2]))) {
    ++rejected_; return;
  }
  *star = '\0';
  char* fields[20] = {line_};
  std::size_t count = 1;
  for (char* p = line_; *p; ++p) {
    if (*p == ',') {
      if (count == 20) { ++rejected_; return; }
      *p = '\0'; fields[count++] = p + 1;
    }
  }
  if (std::strcmp(fields[0], "GPRMC") != 0 &&
      std::strcmp(fields[0], "GNRMC") != 0) return;
  // An incomplete or invalid RMC must never preserve a previously valid fix.
  nav_.valid = false;
  if (count < 10) { ++rejected_; return; }
  if (std::strcmp(fields[2], "V") == 0) {
    nav_.updated_ms = now_ms; ++accepted_; return;
  }
  Navigation next;
  double knots;
  if (std::strcmp(fields[2], "A") != 0 ||
      !coordinate(fields[3], fields[4], true, next.latitude) ||
      !coordinate(fields[5], fields[6], false, next.longitude) ||
      !number(fields[7], knots) || knots > 1000 ||
      (count > 12 && (std::strcmp(fields[12], "N") == 0 ||
                      std::strcmp(fields[12], "S") == 0))) {
    ++rejected_; return;
  }
  next.speed_kmh = knots * 1.852;
  next.valid = true;
  next.updated_ms = now_ms;
  nav_ = next;
  ++accepted_;
}

Navigation Nmea::navigation(std::uint32_t now_ms) const {
  Navigation result = nav_;
  if (static_cast<std::uint32_t>(now_ms - nav_.updated_ms) > 3000)
    result.valid = false;
  return result;
}
}
