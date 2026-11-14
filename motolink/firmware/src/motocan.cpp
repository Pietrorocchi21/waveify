#include "motolink/motocan.hpp"
#include <esp_log.h>
#include <esp_gap_ble_api.h>
#include <esp_gattc_api.h>
#include <esp_bt.h>
#include <esp_bt_main.h>
#include <string.h>
#include <inttypes.h>

static const char* TAG = "MotoCanClient";

// UUIDs for MotoCAN Adapter service
static const esp_bt_uuid_t MOTOCAN_SERVICE_UUID = {
    .len = ESP_UUID_LEN_128,
    .uuid = {.uuid128 = {0xFB, 0x34, 0x9B, 0x5F, 0x80, 0x00, 0x00, 0x80, 0x00, 0x10, 0x00, 0x00, 0x4E, 0x41, 0x43, 0x4F, 0x4F, 0x54, 0x4F, 0x4D}}
};

static const esp_bt_uuid_t MOTOCAN_DATA_UUID = {
    .len = ESP_UUID_LEN_128,
    .uuid = {.uuid128 = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41, 0x54, 0x41, 0x44}}
};

static const esp_bt_uuid_t MOTOCAN_CMD_UUID = {
    .len = ESP_UUID_LEN_128,
    .uuid = {.uuid128 = {0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x44, 0x4D, 0x43, 0x43}}
};

static const esp_bt_uuid_t MOTOCAN_INFO_UUID = {
    .len = ESP_UUID_LEN_128,
    .uuid = {.uuid128 = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4F, 0x46, 0x4E, 0x49}}
};

namespace motolink {

static esp_gattc_char_elem_t* g_chars = nullptr;
static int g_char_count = 0;

MotoCanClient::MotoCanClient() : 
    _state(STATE_IDLE),
    _mode(Mode::off),
    _initialized(false),
    _connected(false),
    _conn_id(0xFFFF),
    _service_handle(0),
    _data_char_handle(0),
    _cmd_char_handle(0),
    _info_char_handle(0),
    _scan_start_ms(0),
    _last_data_ms(0),
    _connect_timeout_ms(0),
    _last_conn_attempt_ms(0) {
    memset(_adapter_name, 0, sizeof(_adapter_name));
    memset(_connected_device_name, 0, sizeof(_connected_device_name));
    memset(&_data, 0, sizeof(_data));
    memset(&_info, 0, sizeof(_info));
}

bool MotoCanClient::begin(uint32_t now_ms, const char* adapter_name_prefix) {
    ESP_LOGI(TAG, "Initializing MotoCAN BLE Client...");

    if (_initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return true;
    }

    strncpy(_adapter_name, adapter_name_prefix ? adapter_name_prefix : "MotoCAN", sizeof(_adapter_name) - 1);

    // BT controller and Bluedroid should be initialized in app_main before calling this
    // We just set up our state here
    _mode = Mode::scanning;
    _state = MotoCanState::disconnected;
    _initialized = true;
    _scan_start_ms = now_ms;
    _last_conn_attempt_ms = 0;

    ESP_LOGI(TAG, "MotoCAN Client ready, will scan for: %s*", _adapter_name);
    return true;
}

void MotoCanClient::end() {
    if (!_initialized) return;

    if (_connected) {
        disconnect();
    }

    if (g_chars) {
        free(g_chars);
        g_chars = nullptr;
        g_char_count = 0;
    }

    _initialized = false;
    _mode = Mode::off;
    _state = MotoCanState::disconnected;
    ESP_LOGI(TAG, "MotoCAN Client stopped");
}

void MotoCanClient::process(uint32_t now_ms) {
    if (!_initialized) return;

    switch (_mode) {
        case Mode::off:
            break;

        case Mode::scanning:
            if (now_ms - _scan_start_ms > 30000) {
                // Scan timeout, restart
                ESP_LOGW(TAG, "Scan timeout, restarting...");
                _scan_start_ms = now_ms;
                esp_ble_gap_start_scanning(30);
            }
            break;

        case Mode::connecting:
            if (now_ms - _connect_timeout_ms > 10000) {
                ESP_LOGE(TAG, "Connection timeout");
                _mode = Mode::scanning;
                _state = MotoCanState::disconnected;
                _scan_start_ms = now_ms;
                esp_ble_gap_start_scanning(30);
            }
            break;

        case Mode::connected:
            // Check if data is stale
            if (_connected && (now_ms - _last_data_ms > 5000)) {
                ESP_LOGW(TAG, "No data from adapter for 5s, requesting...");
                request_data();
            }
            break;
    }
}

bool MotoCanClient::start_scan(uint32_t now_ms) {
    if (!_initialized) return false;

    ESP_LOGI(TAG, "Starting scan for MotoCAN adapters...");
    _mode = Mode::scanning;
    _state = MotoCanState::disconnected;
    _scan_start_ms = now_ms;

    esp_ble_scan_params_t scan_params = {
        .scan_type = BLE_SCAN_TYPE_ACTIVE,
        .own_addr_type = BLE_ADDR_TYPE_PUBLIC,
        .scan_filter_policy = BLE_SCAN_FILTER_ALLOW_ALL,
        .scan_interval = 0x50,
        .scan_window = 0x30,
        .scan_duplicate = BLE_SCAN_DUPLICATE_DISABLE
    };
    esp_ble_gap_set_scan_params(&scan_params);
    esp_ble_gap_start_scanning(30);  // 30 seconds

    return true;
}

bool MotoCanClient::connect(const char* device_name) {
    // Connection is handled via GAP event callback
    // This is a placeholder for manual connection
    return false;
}

void MotoCanClient::disconnect() {
    if (!_connected) return;

    ESP_LOGI(TAG, "Disconnecting from MotoCAN adapter...");
    esp_ble_gattc_close(_gattc_if, _conn_id);
    _connected = false;
    _mode = Mode::scanning;
    _state = MotoCanState::disconnected;
    _scan_start_ms = esp_timer_get_time() / 1000;
    esp_ble_gap_start_scanning(30);
}

bool MotoCanClient::is_connected() const {
    return _connected;
}

bool MotoCanClient::get_data(MotoData& data) const {
    if (!_data.valid) return false;
    data = _data;
    return true;
}

bool MotoCanClient::update_data(const uint8_t* payload, size_t len, uint32_t now_ms) {
    if (len != sizeof(MotoData)) {
        ESP_LOGW(TAG, "Invalid data length: %d expected %d", len, sizeof(MotoData));
        return false;
    }

    memcpy(&_data, payload, len);
    _data.valid = true;
    _data.timestamp_ms = now_ms;
    _last_data_ms = now_ms;
    _state = MotoCanState::data_ready;

    ESP_LOGD(TAG, "Updated MotoData: RPM=%d, Speed=%d, Temp=%d", 
             _data.rpm, _data.speed_kmh, _data.engine_temp_c);
    return true;
}

bool MotoCanClient::request_data() {
    if (!_connected || _cmd_char_handle == 0) return false;

    uint8_t cmd = static_cast<uint8_t>(MotoCanCmd::request_data);
    esp_err_t err = esp_ble_gattc_write_char(_gattc_if, _conn_id, _cmd_char_handle,
                                             sizeof(cmd), &cmd, ESP_GATT_WRITE_TYPE_RSP, ESP_GATT_AUTH_REQ_NONE);
    return err == ESP_OK;
}

bool MotoCanClient::request_faults() {
    if (!_connected || _cmd_char_handle == 0) return false;

    uint8_t cmd = static_cast<uint8_t>(MotoCanCmd::request_faults);
    esp_err_t err = esp_ble_gattc_write_char(_gattc_if, _conn_id, _cmd_char_handle,
                                             sizeof(cmd), &cmd, ESP_GATT_WRITE_TYPE_RSP, ESP_GATT_AUTH_REQ_NONE);
    return err == ESP_OK;
}

bool MotoCanClient::clear_faults() {
    if (!_connected || _cmd_char_handle == 0) return false;

    uint8_t cmd = static_cast<uint8_t>(MotoCanCmd::clear_faults);
    esp_err_t err = esp_ble_gattc_write_char(_gattc_if, _conn_id, _cmd_char_handle,
                                             sizeof(cmd), &cmd, ESP_GATT_WRITE_TYPE_RSP, ESP_GATT_AUTH_REQ_NONE);
    return err == ESP_OK;
}

bool MotoCanClient::get_info(MotoCanInfo& info) {
    if (!_connected || _info_char_handle == 0) return false;

    // For read, we use read characteristic
    esp_err_t err = esp_ble_gattc_read_char(_gattc_if, _conn_id, _info_char_handle,
                                            ESP_GATT_AUTH_REQ_NONE);
    if (err == ESP_OK) {
        // Data will come via callback
        info = _info;
        return true;
    }
    return false;
}

// GAP callback handler (called from app_main GAP event handler)
void MotoCanClient::handle_gap_event(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t* param) {
    if (!_initialized) return;

    switch (event) {
        case ESP_GAP_BLE_SCAN_PARAM_SET_COMPLETE_EVT:
            ESP_LOGD(TAG, "Scan params set");
            break;

        case ESP_GAP_BLE_SCAN_START_COMPLETE_EVT:
            if (param->scan_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
                ESP_LOGI(TAG, "Scan started");
            } else {
                ESP_LOGE(TAG, "Scan start failed: %d", param->scan_start_cmpl.status);
            }
            break;

        case ESP_GAP_BLE_SCAN_RESULT_EVT: {
            esp_ble_gap_cb_param_t::ble_scan_result_evt_param_t& scan = param->scan_rst;
            if (scan.search_evt == ESP_GAP_SEARCH_INQ_RES_EVT) {
                // Check device name
                uint8_t* name = nullptr;
                uint8_t name_len = 0;
                esp_ble_resolve_adv_data(scan.ble_adv, ESP_BLE_AD_TYPE_NAME_CMPL, &name_len);
                if (name_len == 0) {
                    esp_ble_resolve_adv_data(scan.ble_adv, ESP_BLE_AD_TYPE_NAME_SHORT, &name_len);
                }
                if (name_len > 0) {
                    name = (uint8_t*)malloc(name_len + 1);
                    esp_ble_resolve_adv_data(scan.ble_adv, ESP_BLE_AD_TYPE_NAME_CMPL, &name_len);
                    if (name_len == 0) {
                        esp_ble_resolve_adv_data(scan.ble_adv, ESP_BLE_AD_TYPE_NAME_SHORT, &name_len);
                    }
                    if (name_len > 0) {
                        memcpy(name, scan.ble_adv + 31 - name_len, name_len); // approximate
                        name[name_len] = 0;
                        if (strncmp((char*)name, _adapter_name, strlen(_adapter_name)) == 0) {
                            ESP_LOGI(TAG, "Found MotoCAN adapter: %s", name);
                            esp_ble_gap_stop_scanning();
                            _mode = Mode::connecting;
                            _state = MotoCanState::connecting;
                            _connect_timeout_ms = esp_timer_get_time() / 1000;
                            esp_ble_gattc_open(_gattc_if, scan.bda, scan.ble_addr_type, true);
                        }
                        free(name);
                    }
                }
            }
            break;
        }

        case ESP_GAP_BLE_SCAN_STOP_COMPLETE_EVT:
            ESP_LOGD(TAG, "Scan stopped");
            break;

        default:
            break;
    }
}

// GATTC callback handler (called from app_main GATTC event handler)
void MotoCanClient::handle_gattc_event(esp_gattc_cb_event_t event, esp_gattc_cb_param_t* param) {
    if (!_initialized) return;

    switch (event) {
        case ESP_GATTC_OPEN_EVT: {
            if (param->open.status == ESP_GATT_OK) {
                ESP_LOGI(TAG, "Connected to adapter, conn_id=%d", param->open.conn_id);
                _conn_id = param->open.conn_id;
                _gattc_if = param->open.gattc_if;
                _connected = true;
                _mode = Mode::connected;
                _state = MotoCanState::connected;
                // Discover services
                esp_ble_gattc_search_service(_gattc_if, _conn_id, nullptr);
            } else {
                ESP_LOGE(TAG, "Connection failed: %d", param->open.status);
                _mode = Mode::scanning;
                _state = MotoCanState::disconnected;
                _scan_start_ms = esp_timer_get_time() / 1000;
                esp_ble_gap_start_scanning(30);
            }
            break;
        }

        case ESP_GATTC_SEARCH_CMPL_EVT: {
            ESP_LOGI(TAG, "Service discovery complete");
            // Find our service and characteristics
            uint16_t count = 0;
            esp_ble_gattc_get_attr_count(_gattc_if, _conn_id, ESP_GATT_DB_CHARACTERISTIC,
                                         _service_handle, 0xFFFF, 0, &count);
            if (count > 0) {
                if (g_chars) free(g_chars);
                g_chars = (esp_gattc_char_elem_t*)malloc(count * sizeof(esp_gattc_char_elem_t));
                g_char_count = count;
                esp_ble_gattc_get_char_by_uuid(_gattc_if, _conn_id, _service_handle, 0xFFFF,
                                               &MOTOCAN_SERVICE_UUID, g_chars, &count);
            }
            break;
        }

        case ESP_GATTC_GET_CHAR_BY_UUID_EVT: {
            if (param->get_char_by_uuid.status == ESP_GATT_OK && g_char_count > 0) {
                for (int i = 0; i < g_char_count; i++) {
                    if (memcmp(g_chars[i].uuid.uuid.uuid128, MOTOCAN_DATA_UUID.uuid.uuid128, 16) == 0) {
                        _data_char_handle = g_chars[i].char_handle;
                        ESP_LOGI(TAG, "Found DATA char handle: 0x%04X", _data_char_handle);
                        // Enable notifications
                        uint16_t cccd = 0x0001;
                        esp_ble_gattc_write_char_descr(_gattc_if, _conn_id, _data_char_handle + 1,
                                                       2, (uint8_t*)&cccd, ESP_GATT_WRITE_TYPE_RSP, ESP_GATT_AUTH_REQ_NONE);
                    } else if (memcmp(g_chars[i].uuid.uuid.uuid128, MOTOCAN_CMD_UUID.uuid.uuid128, 16) == 0) {
                        _cmd_char_handle = g_chars[i].char_handle;
                        ESP_LOGI(TAG, "Found CMD char handle: 0x%04X", _cmd_char_handle);
                    } else if (memcmp(g_chars[i].uuid.uuid.uuid128, MOTOCAN_INFO_UUID.uuid.uuid128, 16) == 0) {
                        _info_char_handle = g_chars[i].char_handle;
                        ESP_LOGI(TAG, "Found INFO char handle: 0x%04X", _info_char_handle);
                    }
                }
                _state = MotoCanState::data_ready;
            }
            break;
        }

        case ESP_GATTC_NOTIFY_EVT: {
            if (param->notify.handle == _data_char_handle && param->notify.value_len == sizeof(MotoData)) {
                update_data(param->notify.value, param->notify.value_len, esp_timer_get_time() / 1000);
            }
            break;
        }

        case ESP_GATTC_READ_CHAR_EVT: {
            if (param->read.status == ESP_GATT_OK && param->read.handle == _info_char_handle) {
                if (param->read.value_len == sizeof(MotoCanInfo)) {
                    memcpy(&_info, param->read.value, sizeof(MotoCanInfo));
                    ESP_LOGI(TAG, "Read adapter info: %s v%s", _info.brand_name, _info.firmware_version);
                }
            }
            break;
        }

        case ESP_GATTC_CLOSE_EVT: {
            ESP_LOGI(TAG, "Disconnected from adapter");
            _connected = false;
            _conn_id = 0xFFFF;
            _service_handle = 0;
            _data_char_handle = 0;
            _cmd_char_handle = 0;
            _info_char_handle = 0;
            _mode = Mode::scanning;
            _state = MotoCanState::disconnected;
            _scan_start_ms = esp_timer_get_time() / 1000;
            esp_ble_gap_start_scanning(30);
            break;
        }

        default:
            break;
    }
}

MotoCanClient::Mode MotoCanClient::mode() const {
    return _mode;
}

MotoCanState MotoCanClient::state() const {
    return _state;
}

}  // namespace motolink
