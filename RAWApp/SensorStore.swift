import SwiftUI
import CoreLocation
import CoreMotion
import CoreTelephony
import Network
import UIKit
import Darwin

@MainActor
final class SensorStore: NSObject, ObservableObject {
    enum SensorSection: String, CaseIterable, Identifiable {
        case location = "Location / GNSS"
        case motion = "Motion"
        case barometer = "Barometer"
        case magnetometer = "Magnetometer"
        case radio = "Cellular / Radio"
        case device = "Device / CPU"

        var id: String { rawValue }
    }

    @Published var selectedSection: SensorSection?

    @Published var locationSummary: [SensorValue] = []
    @Published var motionSummary: [SensorValue] = []
    @Published var barometerSummary: [SensorValue] = []
    @Published var magnetometerSummary: [SensorValue] = []
    @Published var radioSummary: [SensorValue] = []
    @Published var deviceSummary: [SensorValue] = []

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let telephonyInfo = CTTelephonyNetworkInfo()

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "radio.path.monitor")

    private var cpuTimer: Timer?
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true

        UIDevice.current.isBatteryMonitoringEnabled = true

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        locationSummary = [SensorValue(name: "Permission", value: "Waiting for location authorization")]
        locationManager.requestWhenInUseAuthorization()

        startMotionSensors()
        startBarometer()
        startMagnetometer()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.radioSummary = self?.buildRadioSummary(path: path) ?? []
            }
        }
        pathMonitor.start(queue: pathQueue)

        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDeviceSummary()
        }
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDeviceSummary()
        }

        cpuTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDeviceSummary()
            }
        }
        updateDeviceSummary()
        radioSummary = buildRadioSummary(path: pathMonitor.currentPath)
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopMagnetometerUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingLocation()
        if #available(iOS 14.0, *) {
            locationManager.stopUpdatingHeading()
        }
        pathMonitor.cancel()
        cpuTimer?.invalidate()
    }

    func values(for section: SensorSection) -> [SensorValue] {
        switch section {
        case .location: return locationSummary
        case .motion: return motionSummary
        case .barometer: return barometerSummary
        case .magnetometer: return magnetometerSummary
        case .radio: return radioSummary
        case .device: return deviceSummary
        }
    }

    private func startMotionSensors() {
        guard motionManager.isDeviceMotionAvailable else {
            motionSummary = [SensorValue(name: "Motion", value: "Device motion is unavailable on this hardware")]
            return
        }

        if #available(iOS 11.0, *), CMMotionActivityManager.authorizationStatus() == .denied {
            motionSummary = [SensorValue(name: "Permission", value: "Motion access denied in Settings")]
            return
        }

        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.motionSummary = [SensorValue(name: "Motion Error", value: error.localizedDescription)]
                return
            }
            guard let motion else { return }
            self.motionSummary = [
                SensorValue(name: "Acceleration X/Y/Z (g)", value: String(format: "%.3f / %.3f / %.3f", motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z)),
                SensorValue(name: "Gyro X/Y/Z (rad/s)", value: String(format: "%.3f / %.3f / %.3f", motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)),
                SensorValue(name: "Gravity X/Y/Z", value: String(format: "%.3f / %.3f / %.3f", motion.gravity.x, motion.gravity.y, motion.gravity.z)),
                SensorValue(name: "Attitude roll/pitch/yaw", value: String(format: "%.3f / %.3f / %.3f", motion.attitude.roll, motion.attitude.pitch, motion.attitude.yaw))
            ]
        }
    }

    private func startMagnetometer() {
        guard motionManager.isMagnetometerAvailable else {
            magnetometerSummary = [SensorValue(name: "Magnetometer", value: "Unavailable on this hardware")]
            return
        }

        motionManager.magnetometerUpdateInterval = 0.3
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            guard let self else { return }
            if let error {
                self.magnetometerSummary = [SensorValue(name: "Magnetometer Error", value: error.localizedDescription)]
                return
            }
            guard let data else { return }
            self.magnetometerSummary = [
                SensorValue(name: "Magnetic Field X/Y/Z (µT)", value: String(format: "%.2f / %.2f / %.2f", data.magneticField.x, data.magneticField.y, data.magneticField.z))
            ]
        }
    }

    private func startBarometer() {
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    self.barometerSummary = [SensorValue(name: "Barometer Error", value: error.localizedDescription)]
                    return
                }
                guard let data else { return }
                self.barometerSummary = [
                    SensorValue(name: "Pressure (kPa)", value: String(format: "%.2f", data.pressure.doubleValue)),
                    SensorValue(name: "Relative Altitude (m)", value: String(format: "%.2f", data.relativeAltitude.doubleValue))
                ]
            }
        } else {
            barometerSummary = [SensorValue(name: "Barometer", value: "Not available on this device")]
        }
    }

    private func buildRadioSummary(path: NWPath) -> [SensorValue] {
        var values: [SensorValue] = [
            SensorValue(name: "Network status", value: path.status == .satisfied ? "Connected" : "Not connected"),
            SensorValue(name: "Uses Wi‑Fi", value: path.usesInterfaceType(.wifi) ? "Yes" : "No"),
            SensorValue(name: "Uses Cellular", value: path.usesInterfaceType(.cellular) ? "Yes" : "No"),
            SensorValue(name: "Is Expensive", value: path.isExpensive ? "Yes" : "No"),
            SensorValue(name: "Is Constrained", value: path.isConstrained ? "Yes" : "No")
        ]

        if let technologies = telephonyInfo.serviceCurrentRadioAccessTechnology {
            let joined = technologies.map { "\($0.key): \($0.value)" }.joined(separator: " | ")
            values.append(SensorValue(name: "Radio Access Tech", value: joined.isEmpty ? "Unknown" : joined))
        } else {
            values.append(SensorValue(name: "Radio Access Tech", value: "Unavailable (Wi‑Fi only iPad / Vision Pro / no SIM)"))
        }

        if let carriers = telephonyInfo.serviceSubscriberCellularProviders {
            let carrierValue = carriers.compactMap { _, carrier in
                let carrierName = carrier.carrierName ?? "Unknown"
                let mobileCountryCode = carrier.mobileCountryCode ?? "--"
                let mobileNetworkCode = carrier.mobileNetworkCode ?? "--"
                return "\(carrierName) (MCC:\(mobileCountryCode) MNC:\(mobileNetworkCode))"
            }.joined(separator: " | ")
            values.append(SensorValue(name: "Carrier", value: carrierValue.isEmpty ? "Unknown" : carrierValue))
        }

        values.append(SensorValue(name: "Signal Strength", value: "Not exposed via public iOS API"))
        return values
    }

    private func updateDeviceSummary() {
        let processInfo = ProcessInfo.processInfo
        let physicalMemoryGiB = Double(processInfo.physicalMemory) / 1_073_741_824

        deviceSummary = [
            SensorValue(name: "Thermal State", value: thermalDescription(processInfo.thermalState)),
            SensorValue(name: "Low Power Mode", value: processInfo.isLowPowerModeEnabled ? "Enabled" : "Disabled"),
            SensorValue(name: "Battery Level", value: batteryLevelString()),
            SensorValue(name: "Battery State", value: batteryStateString()),
            SensorValue(name: "Physical Memory (GiB)", value: String(format: "%.2f", physicalMemoryGiB)),
            SensorValue(name: "CPU Usage", value: cpuUsageString())
        ]
    }

    private func thermalDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func batteryLevelString() -> String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "Unknown" }
        return String(format: "%.0f%%", level * 100)
    }

    private func batteryStateString() -> String {
        switch UIDevice.current.batteryState {
        case .charging: return "Charging"
        case .full: return "Full"
        case .unplugged: return "Unplugged"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private func cpuUsageString() -> String {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return "Unavailable" }

        let user = Double(cpuInfo.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return "Unavailable" }

        let usage = ((user + system + nice) / total) * 100
        return String(format: "%.1f%%", usage)
    }
}

extension SensorStore: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            var values: [SensorValue] = [
                SensorValue(name: "Latitude", value: String(format: "%.7f", location.coordinate.latitude)),
                SensorValue(name: "Longitude", value: String(format: "%.7f", location.coordinate.longitude)),
                SensorValue(name: "Altitude (m)", value: String(format: "%.2f", location.altitude)),
                SensorValue(name: "Speed (m/s)", value: String(format: "%.2f", max(0, location.speed))),
                SensorValue(name: "Course (°)", value: String(format: "%.2f", location.course)),
                SensorValue(name: "Horizontal Accuracy (m)", value: String(format: "%.2f", location.horizontalAccuracy)),
                SensorValue(name: "Vertical Accuracy (m)", value: String(format: "%.2f", location.verticalAccuracy)),
                SensorValue(name: "Timestamp", value: location.timestamp.formatted())
            ]

            if #available(iOS 15.0, *), let sourceInfo = location.sourceInformation {
                values.append(SensorValue(name: "Simulated by Software", value: sourceInfo.isSimulatedBySoftware ? "Yes" : "No"))
                values.append(SensorValue(name: "Produced by Accessory", value: sourceInfo.isProducedByAccessory ? "Yes" : "No"))
            }

            values.append(SensorValue(name: "Satellite IDs / Galileo PRN", value: "Not exposed via public Core Location API"))
            self.locationSummary = values
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationSummary = [SensorValue(name: "Location Error", value: error.localizedDescription)]
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
                if #available(iOS 14.0, *), CLLocationManager.headingAvailable() {
                    manager.startUpdatingHeading()
                }
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                self.locationSummary = [SensorValue(name: "Permission", value: "Location access denied or restricted")]
            @unknown default:
                break
            }
        }
    }
}
