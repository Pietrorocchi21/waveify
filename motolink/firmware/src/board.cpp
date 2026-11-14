#include "motolink/board.hpp"
#include "driver/uart.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "driver/adc.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "motolink/imu.hpp"
#include "motolink/motocan.hpp"

namespace motolink {

static constexpr char tag[] = "board";

static spi_device_handle_t imu_spi_handle = nullptr;
static adc_oneshot_unit_handle_t adc_handle = nullptr;
static adc_cali_handle_t adc_cali_handle = nullptr;

uint32_t board_init(const BoardConfig& cfg, uint32_t now_ms,
                    Nmea* gnss, Imu* imu, Ble* ble, Storage* storage, Can* can,
                    MotoCanClient* motocan, PowerMonitor* power,
                    StatusLed* led, ServiceButton* btn) {
  uint32_t initialized = 0;

  if (led) {
    led->begin(cfg.led_gpio, cfg.led_active_high);
    led->set_pattern(LedPattern::slow_blink);
    initialized |= MOD_LED;
  }

  if (btn) {
    btn->begin(cfg.btn_gpio, cfg.btn_active_low);
    initialized |= MOD_BTN;
  }

  if (gnss && CONFIG_MOTOLINK_GNSS_ENABLED) {
    uart_config_t uart_config = {};
    uart_config.baud_rate = cfg.gnss_baud;
    uart_config.data_bits = UART_DATA_8_BITS;
    uart_config.parity = UART_PARITY_DISABLE;
    uart_config.stop_bits = UART_STOP_BITS_1;
    uart_config.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;
    uart_config.source_clk = UART_SCLK_DEFAULT;

    esp_err_t err = uart_param_config(UART_NUM_1, &uart_config);
    if (err == ESP_OK) {
      err = uart_driver_install(UART_NUM_1, 2048, 0, 0, nullptr, 0);
    }
    if (err == ESP_OK) {
      err = uart_set_pin(UART_NUM_1, UART_PIN_NO_CHANGE, cfg.gnss_rx,
                         UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    }
    if (err == ESP_OK) {
      initialized |= MOD_GNSS;
      ESP_LOGI(tag, "GNSS UART initialized on GPIO %d @ %lu baud", cfg.gnss_rx, cfg.gnss_baud);
    } else {
      ESP_LOGE(tag, "GNSS UART init failed: %s", esp_err_to_name(err));
    }
  }

  if (imu && CONFIG_MOTOLINK_IMU_ENABLED) {
    spi_bus_config_t buscfg = {};
    buscfg.mosi_io_num = GPIO_NUM_11;
    buscfg.miso_io_num = GPIO_NUM_13;
    buscfg.sclk_io_num = GPIO_NUM_12;
    buscfg.quadwp_io_num = -1;
    buscfg.quadhd_io_num = -1;
    buscfg.max_transfer_sz = 4096;
    buscfg.flags = SPICOMMON_BUSFLAG_MASTER;

    esp_err_t err = spi_bus_initialize(static_cast<spi_host_device_t>(cfg.imu_spi_host), &buscfg, SPI_DMA_CH_AUTO);
    if (err != ESP_OK) {
      ESP_LOGE(tag, "SPI bus init failed: %s", esp_err_to_name(err));
    } else {
      spi_device_interface_config_t devcfg = {};
      devcfg.clock_speed_hz = 1000000;
      devcfg.mode = 0;
      devcfg.spics_io_num = cfg.imu_cs;
      devcfg.queue_size = 4;

      err = spi_bus_add_device(static_cast<spi_host_device_t>(cfg.imu_spi_host), &devcfg, &imu_spi_handle);
      if (err != ESP_OK) {
        ESP_LOGE(tag, "SPI device add failed: %s", esp_err_to_name(err));
      } else {
        imu_set_spi_handle(imu_spi_handle);
        if (imu->begin(now_ms)) {
          initialized |= MOD_IMU;
          ESP_LOGI(tag, "IMU initialized on SPI host %d CS %d", cfg.imu_spi_host, cfg.imu_cs);
          gpio_config_t io_conf = {};
          io_conf.intr_type = GPIO_INTR_POSEDGE;
          io_conf.mode = GPIO_MODE_INPUT;
          io_conf.pin_bit_mask = (1ULL << cfg.imu_int);
          io_conf.pull_down_en = GPIO_PULLDOWN_ENABLE;
          gpio_config(&io_conf);
        }
      }
    }
  }

  if (ble && CONFIG_MOTOLINK_BLE_ENABLED) {
    if (ble->begin(now_ms, cfg.ble_name)) {
      initialized |= MOD_BLE;
      ESP_LOGI(tag, "BLE initialized");
    }
  }

  if (storage && CONFIG_MOTOLINK_STORAGE_ENABLED) {
    if (storage->begin(now_ms)) {
      initialized |= MOD_STORAGE;
      ESP_LOGI(tag, "Storage initialized");
    }
  }

  // CAN is DISABLED on Core (handled by MotoCAN Adapter via BLE)
  if (can && CONFIG_MOTOLINK_CAN_ENABLED) {
    if (can->begin(now_ms, Can::Mode::listen_only, cfg.can_bitrate)) {
      initialized |= MOD_CAN;
      ESP_LOGI(tag, "CAN initialized");
    }
  }

  // Power monitoring (ADC)
  if (power && CONFIG_MOTOLINK_POWER_MONITOR) {
    adc_oneshot_unit_init_cfg_t init_config = {
      .unit_id = ADC_UNIT_1,
      .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    esp_err_t err = adc_oneshot_new_unit(&init_config, &adc_handle);
    if (err == ESP_OK) {
      adc_oneshot_chan_cfg_t chan_config = {
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_12,
      };
      err = adc_oneshot_config_channel(adc_handle, static_cast<adc_channel_t>(cfg.power_adc_channel), &chan_config);
    }
    if (err == ESP_OK) {
      adc_cali_curve_fitting_config_t cali_config = {
        .unit_id = ADC_UNIT_1,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_12,
      };
      err = adc_cali_create_scheme_curve_fitting(&cali_config, &adc_cali_handle);
    }
    if (err == ESP_OK) {
      power->initialized = true;
      power->adc_channel = cfg.power_adc_channel;
      power->vref_mv = 3300;
      power->divider_ratio = 11;  // 10:1 divider for 12V system
      initialized |= MOD_POWER;
      ESP_LOGI(tag, "Power monitor initialized on ADC channel %d", cfg.power_adc_channel);
    } else {
      ESP_LOGE(tag, "Power monitor init failed: %s", esp_err_to_name(err));
    }
  }

  // MotoCAN Adapter BLE Client
  if (motocan && CONFIG_MOTOLINK_BLE_CLIENT_ENABLED) {
    if (motocan->begin(now_ms, cfg.motocan_name_prefix)) {
      initialized |= MOD_MOTOCAN;
      ESP_LOGI(tag, "MotoCAN client initialized");
    }
  }

  return initialized;
}

void board_deinit(Nmea* gnss, Imu* imu, Ble* ble, Storage* storage, Can* can,
                  MotoCanClient* motocan, PowerMonitor* power,
                  StatusLed* led, ServiceButton* btn) {
  if (gnss) uart_driver_delete(UART_NUM_1);
  if (imu) imu->end();
  if (ble) ble->end();
  if (storage) storage->end();
  if (can) can->end();
  if (motocan) motocan->end();
  if (power && power->initialized) {
    if (adc_cali_handle) adc_cali_delete_scheme_curve_fitting(adc_cali_handle);
    if (adc_handle) adc_oneshot_del_unit(adc_handle);
    power->initialized = false;
  }
  if (led) led->end();
  if (btn) btn->end();
}

void board_update(uint32_t now_ms, Nmea* gnss, Imu* imu, Ble* ble,
                  Storage* storage, Can* can, MotoCanClient* motocan,
                  PowerMonitor* power, StatusLed* led, ServiceButton* btn) {
  if (led) led->update(now_ms);
  if (btn) btn->poll(now_ms);
  if (ble) ble->process(now_ms);
  if (can) can->process(now_ms);
  if (motocan) motocan->process(now_ms);
  if (power && power->initialized) {
    // Power monitor reading handled by app_main
  }
  if (storage) storage->sync();
}

}  // namespace motolink
