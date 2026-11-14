# MotoLink firmware 0.1.0

Target: ESP32-S3-DevKitC-1 N16R8. Progetto ESP-IDF in espidf/;
nucleo e moduli hardware indipendenti dalla scheda in src/.
Riferimento toolchain: ESP-IDF 5.4.1. Non ancora compilato o provato su hardware
in questa sessione: ESP-IDF, CMake e compilatore non risultano disponibili.

## Architettura

```
firmware/
+-- include/motolink/     # Header pubblici (core + hardware modules)
|   +-- core.hpp         # State machine, comandi, errori
|   +-- nmea.hpp         # Parser NMEA RMC (GPS)
|   +-- imu.hpp          # BMI270 accelerometro/giroscopio
|   +-- ble.hpp          # BLE GATT service per app
|   +-- storage.hpp      # microSD logging (FATFS)
|   +-- can.hpp          # TWAI/CAN bus (listen-only)
|   +-- status.hpp       # LED pattern + pulsante service
|   +-- board.hpp        # Pin mapping da Kconfig, init board
+-- src/                 # Implementazioni C++ (board-independent)
+-- tests/               # Unit test nativi (CMake + CTest)
+-- espidf/              # Progetto ESP-IDF
    +-- main/app_main.cpp    # Entry point, main loop, console
    +-- main/Kconfig.projbuild # Configurazione pin e feature
    +-- sdkconfig.defaults   # Default SDK config
    +-- CMakeLists.txt
```

## Moduli implementati

| Modulo | File | Stato | Note |
|--------|------|-------|------|
| Core | core.cpp/hpp | OK | State machine, watchdog, comandi |
| GNSS/NMEA | nmea.cpp/hpp | OK | Parser RMC, checksum, coordinate |
| IMU (BMI270) | imu.cpp/hpp | Stub | SPI, calibrazione, self-test |
| BLE | ble.cpp/hpp | Stub | GATT service, notify, comandi |
| Storage (SD) | storage.cpp/hpp | Stub | FATFS, log binari, CRC32 |
| CAN (TWAI) | can.cpp/hpp | Stub | Listen-only, filtri, statistiche |
| Status LED | status.cpp/hpp | Stub | Pattern, PWM breathing |
| Service Button | status.cpp/hpp | Stub | Debounce, click/long press |
| Board init | board.cpp/hpp | Stub | Kconfig-driven pin mapping |

## Compilare e caricare

Installare ESP-IDF 5.4.1 con toolchain ESP32-S3. Nel terminale ESP-IDF,
dalla sottocartella espidf:

```
idf.py set-target esp32s3
idf.py menuconfig          # Configura pin e feature in "MotoLink"
idf.py build
idf.py -p COM5 flash monitor
```

Sostituire COM5 con la porta reale. Usare la USB-to-UART della DevKit;
la console USB nativa non e configurata. Configurata flash 16 MB; PSRAM non
ancora abilitata o necessaria. Usare idf.py flash per caricare anche
bootloader e tabella partizioni.

## Console protocollo 1

Comandi maiuscoli seguiti da LF o CRLF, massimo 95 caratteri:

| Comando | Descrizione | Risposta |
|---------|-------------|----------|
| PING | Test connessione | PONG + versione protocollo |
| VERSION | Info firmware | Nome, versione, protocollo |
| STATUS | Stato completo sistema | JSON con stato, heap, moduli, MAC |
| GNSS | Fix GPS corrente | JSON con fix, lat, lon, speed |
| IMU | Campione IMU corrente | JSON con ax,ay,az,gx,gy,gz |
| LED <n> | Imposta pattern LED (0-6) | Conferma pattern |
| STORAGE_INFO | Info SD card | JSON free/total/present |
| CAN_FILTER <idx> <id> <mask> | Filtro CAN acceptance | Conferma o errore |

Pattern LED:
- 0 = off
- 1 = solid on
- 2 = slow blink (1 Hz) - booting, no GPS
- 3 = fast blink (4 Hz) - error/fault
- 4 = heartbeat (double blink) - ready, GPS ok
- 5 = breathing (PWM fade) - ready, no GPS
- 6 = triple blink - BLE connected

Stati: 0 booting, 1 ready, 2 fault.
Errori: 100 = inizializzazione UART GNSS fallita.
I log ESP-IDF condividono la console: il client deve selezionare le righe JSON.
Nessun comando modifica la moto, cancella dati o riavvia la scheda (eccetto long press).

## Pulsante di servizio (GPIO 0 default)

| Pressione | Azione |
|-----------|--------|
| Breve (< 1s) | Triple blink LED, log evento |
| Lunga (1-3s) | Riavvio sistema (esp_restart) |
| Molto lunga (> 3s) | Factory reset (TODO) |
| Doppio click | Toggle logging (TODO) |

## GPS sul banco

Breakout MAX-M10S con UART a 3,3 V; alimentazione secondo specifiche del breakout.
Massa comune, TX GPS verso GPIO configurato (default 4); RX GPS non necessario.
In idf.py menuconfig, menu MotoLink, abilitare GNSS e impostare il baud rate
uguale al ricevitore (proposto 9600). Il firmware non riconfigura il ricevitore:
serve uscita NMEA RMC GP/GN con posizione e velocita. Ricompilare e caricare.

## Test sul PC

Dalla cartella firmware, con CMake e compilatore C++:

```
cmake -S . -B build
cmake --build build --config Debug
ctest --test-dir build -C Debug --output-on-failure
```

Test inclusi: stati core, errore persistente, wrap del clock, checksum NMEA,
coordinate, fix assente e scaduto, valori errati, recupero dopo overflow,
dimensioni struct BLE/storage/CAN, enum LED/button.
Non verificano UART, watchdog, flash, SPI, BLE stack o sensori fisici.
Workflow GitHub dedicato per test nativi e build ESP-IDF: da eseguire dopo il push.

## Prossimi passi per completare l'"hardware reale

1. **IMU BMI270**: Implementare SPI read/write, FOC calibration, interrupt data-ready
2. **BLE**: ESP-IDF Bluedroid stack, GATT service, advertising, bonding NVS
3. **Storage**: SDMMC 1/4-bit, FATFS mount, log rotation, CRC32 verification
4. **CAN**: TWAI driver, timing config per bitrate, acceptance filters, bus-off recovery
5. **LED**: LEDC PWM per breathing pattern, brightness control
6. **Button**: GPIO interrupt + debounce task, double-click detection
7. **Power management**: Deep sleep, wake sources, 12V monitoring
8. **OTA**: Partition table, secure boot, rollback protection

## Riferimenti hardware

Vedi HARDWARE.md per scelta componenti, vincoli e collegamenti.