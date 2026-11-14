#include "motolink/nmea.hpp"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
static void check(bool value) { if (!value) std::abort(); }
static void send(motolink::Nmea& p, const std::string& body, std::uint32_t now) {
  unsigned sum = 0;
  for (char c : body) sum ^= static_cast<unsigned char>(c);
  char suffix[8];
  std::snprintf(suffix, sizeof(suffix), "*%02X\r\n", sum);
  for (char c : "$" + body + suffix) p.feed(c, now);
}
int main() {
  motolink::Nmea p;
  check(!p.navigation(0).valid);
  send(p, "GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W", 100);
  auto n = p.navigation(100);
  check(n.valid);
  check(std::fabs(n.latitude - 48.1173) < 0.000001);
  check(std::fabs(n.longitude - 11.516666667) < 0.000001);
  check(std::fabs(n.speed_kmh - 41.4848) < 0.000001);
  check(!p.navigation(3101).valid);
  send(p, "GNRMC,123519,V,,,,,,,230394,,,N", 200);
  check(!p.navigation(200).valid);
  send(p, "GNRMC,123519,A,4807.038,S,01131.000,W,0,0,230394,,,A", 300);
  check(p.navigation(300).valid && p.navigation(300).latitude < 0);
  const auto accepted = p.accepted();
  for (char c : std::string("$GPRMC,bad*00\n")) p.feed(c, 400);
  check(p.accepted() == accepted && p.rejected() > 0);
  send(p, "GPRMC,123519,A,4860.000,N,01131.000,E,1,0,230394", 500);
  check(!p.navigation(500).valid);
  send(p, "GPRMC,123519,A,9000.001,N,01131.000,E,1,0,230394", 600);
  check(!p.navigation(600).valid);
  send(p, "GPRMC,123519,A,4807.038,N,01131.000,E,nan,0,230394", 700);
  check(!p.navigation(700).valid);
  p.feed('$', 800);
  for (int i = 0; i < 200; ++i) p.feed('a', 800);
  p.feed('\n', 800);
  send(p, "GPRMC,123519,A,4807.038,N,01131.000,E,1,0,230394", 0xfffffff0u);
  check(p.navigation(0x10u).valid);
  check(!p.navigation(0x1000u).valid);
}
