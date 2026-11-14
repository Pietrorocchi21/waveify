cmake_minimum_required(VERSION 3.16)
project(motolink_core LANGUAGES CXX)

add_library(motolink_core STATIC 
  src/core.cpp 
  src/nmea.cpp
  src/imu.cpp
  src/ble.cpp
  src/storage.cpp
  src/can.cpp
  src/status.cpp
  src/board.cpp
  src/motocan.cpp
)
target_include_directories(motolink_core PUBLIC include)
target_compile_features(motolink_core PUBLIC cxx_std_11)

include(CTest)
if(BUILD_TESTING)
  add_executable(core_test tests/core_test.cpp)
  target_link_libraries(core_test PRIVATE motolink_core)
  add_test(NAME core_test COMMAND core_test)
  add_executable(nmea_test tests/nmea_test.cpp)
  target_link_libraries(nmea_test PRIVATE motolink_core)
  add_test(NAME nmea_test COMMAND nmea_test)
  add_executable(imu_test tests/imu_test.cpp)
  target_link_libraries(imu_test PRIVATE motolink_core)
  add_test(NAME imu_test COMMAND imu_test)
  add_executable(ble_test tests/ble_test.cpp)
  target_link_libraries(ble_test PRIVATE motolink_core)
  add_test(NAME ble_test COMMAND ble_test)
  add_executable(storage_test tests/storage_test.cpp)
  target_link_libraries(storage_test PRIVATE motolink_core)
  add_test(NAME storage_test COMMAND storage_test)
  add_executable(can_test tests/can_test.cpp)
  target_link_libraries(can_test PRIVATE motolink_core)
  add_test(NAME can_test COMMAND can_test)
  add_executable(status_test tests/status_test.cpp)
  target_link_libraries(status_test PRIVATE motolink_core)
  add_test(NAME status_test COMMAND status_test)
endif()
