idf_component_register(
  SRCS "app_main.cpp" "../../src/core.cpp" "../../src/nmea.cpp"
         "../../src/imu.cpp" "../../src/ble.cpp" "../../src/storage.cpp"
         "../../src/can.cpp" "../../src/status.cpp" "../../src/board.cpp"
  INCLUDE_DIRS "../../include"
  REQUIRES driver esp_timer esp_system esp_wifi esp_bt bt_controller
           nvs_flash sdmmc fatfs twai
)
target_compile_features(${COMPONENT_LIB} PUBLIC cxx_std_11)
