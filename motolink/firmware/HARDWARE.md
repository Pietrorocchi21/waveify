# MotoLink v1 — Architettura Modulare Prodotto

Prodotto finale vendibile: MotoLink Core universale + MotoCAN Adapter brand-specific.

## Architettura

```
Moto Centralina CAN
       ↓
[MotoCAN Adapter Brand] → BLE GATT → [MotoLink Core] → App Telefono
```

MotoLink Core riceve dati normalizzati dal adapter via BLE.
Ogni marca ha il suo adapter con connettore e protocollo specifico.

## MotoLink Core - Universale

Dispositivo principale per tutte le moto.

| Parte | Scelta | Funzione |
|-------|--------|----------|
| MCU | ESP32-S3-WROOM-1U-N16R8 | Wi-Fi, BLE, 16MB flash, 8MB PSRAM, antenna esterna |
| Posizione | u-blox MAX-M10S | GNSS UART 3.3V, antenna attiva esterna |
| Movimento | Bosch BMI270 | SPI 3.3V, accel/giro, interrupt data ready |
| Storage | microSD slot push-pull | Logging percorsi, FATFS |
| Alimentazione | LM5164-Q1 12V→5V + LDO 3.3V | Protezione inversione, TVS, fusibile PTC |
| Interazione | LED status + pulsante service | GPIO ESP32-S3 |
| Connettività | BLE 5.0 | Ricezione dati da MotoCAN Adapter |
| Contenitore | IP67 | Vibrazioni moto, tenuta acqua/polvere |

**Pinout Core:**
- UART1: GNSS RX
- SPI2: BMI270 CS/CLK/MOSI/MISO/INT
- GPIO: LED, pulsante, SDMMC
- BLE: GATT client per MotoCAN Adapter

## MotoCAN Adapter - Brand Specific

Bridge CAN→BLE dedicato per ogni marca moto.

| Parte | Scelta | Funzione |
|-------|--------|----------|
| MCU | ESP32-C3 mini | BLE 5.0 low power, UART/SPI |
| CAN Controller | MCP2515 + TCAN1042 | CAN 2.0 500kbps |
| Alimentazione | 12V moto → 3.3V LDO | Protezione |
| Connettore | Specifico marca | Ducati 3-pin, BMW 10-pin, etc. |
| Contenitore | IP65 piccolo | Montaggio sotto sella |

**Adattatori brand:**
- Ducati: connettore 3-pin sotto sella, protocollo CAN 500kbps proprietario
- BMW: connettore 10-pin, protocollo CAN/K-Line
- Kawasaki/Yamaha/Honda: OBD-II o connettore diagnostico specifico
- Aprilia: connettore 4-pin

Ogni adapter ha firmware brand-specific che decodifica PID proprietari e invia dati normalizzati via BLE GATT a MotoLink Core.

## Vantaggi modulare

- MotoLink Core una volta per tutti
- Adapter per marca, plug-and-play
- Aggiornamenti OTA firmware adapter
- Nessun CAN hardware su Core, solo BLE
- Certificazione per marca semplificata
- Scalabile a nuove marche

## Componenti Core da acquistare

**Prototipo:**
- ESP32-S3-DevKitC-1 N16R8
- u-blox MAX-M10S breakout UART
- Antenna GNSS attiva IPEX
- Bosch BMI270 breakout SPI
- microSD breakout SPI
- LM5164-Q1 + LDO TPS79333
- Box IP67

**PCB finale:**
- ESP32-S3-WROOM-1U-N16R8
- MAX-M10S modulo
- BMI270
- microSD slot
- LM5164-Q1 + passive
- LDO 3.3V
- Box IP67

## Componenti Adapter per brand

Per ogni marca:
- ESP32-C3 mini
- MCP2515 + TCAN1042
- Connettore specifico marca
- LDO 12V→3.3V
- Box IP65

## Vincoli

- ESP32-S3 BLE 5.0 come client verso adapter
- Adapter BLE 5.0 come peripheral
- Protocollo GATT custom per dati moto normalizzati
- Nessun accesso diretto CAN su Core
- Alimentazione moto 12V con protezione completa
- Certificazioni CE/FCC per Core + ogni adapter

## Strategia firmware

MotoLink Core:
- ESP-IDF C++
- BLE GATT client per MotoCAN Adapter
- Parser NMEA GNSS
- Driver BMI270 SPI
- Logging SD FATFS
- App BLE per configurazione

MotoCAN Adapter:
- ESP-IDF C++
- BLE GATT server
- MCP2515 SPI CAN
- Decoder protocollo marca-specifico
- Invio dati normalizzati via BLE

## Riferimenti

- ESP32-S3: https://www.espressif.com/en/products/socs/esp32-s3
- MAX-M10S: https://www.u-blox.com/en/product/max-m10-series
- BMI270: https://www.bosch-sensortec.com/en/products/motion-sensors/imus/bmi270
- LM5164-Q1: https://www.ti.com/product/LM5164-Q1

