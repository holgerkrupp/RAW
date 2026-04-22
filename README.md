# RAW

A modern SwiftUI app that presents live, on-device sensor data from iPhone, iPad, and Vision Pro in a `NavigationSplitView` dashboard with a glass-like UI.

## Included live data

- **Location / GNSS** via `CoreLocation`: latitude, longitude, altitude, speed, heading/course, accuracy, timestamps, and source metadata (when available).
- **Motion** via `CoreMotion`: accelerometer (user acceleration), gyroscope (rotation rate), gravity, and device attitude.
- **Magnetometer** via `CoreMotion`: magnetic field XYZ.
- **Barometer** via `CMAltimeter`: pressure and relative altitude.
- **Cellular / Radio** via `Network` + `CoreTelephony`: connectivity state, active interface type, constrained/expensive path flags, carrier info and radio access technology when present.
- **Device / CPU** via `ProcessInfo`, `UIDevice`, and host stats: thermal state, low power mode, battery, physical memory, and CPU load.

## Platform/API notes

Apple does **not** expose everything through public APIs. This project explicitly surfaces those limits in the UI, including:

- Per-satellite GNSS identifiers (GPS/Galileo PRN IDs).
- Raw cellular signal strength (RSSI/RSRP/RSRQ in dBm).

The app compiles for iOS and also includes target platform settings compatible with VisionOS builds in modern Xcode toolchains.

## Open in Xcode

1. Open `RAW.xcodeproj`.
2. Select a physical device (many sensors are unavailable in simulator).
3. Run and grant Location/Motion permissions when prompted.
