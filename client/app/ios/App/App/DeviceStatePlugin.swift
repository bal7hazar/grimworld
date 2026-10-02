import Capacitor
import UIKit

/// The device state SPK-6's run log records (protocol §9 point 9): the thermal state, the battery
/// level and state, Low Power Mode. Its TypeScript side is `src/shell/deviceState.ts`. Registered
/// on the bridge by `ShellViewController`.
@objc(DeviceStatePlugin)
public class DeviceStatePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DeviceStatePlugin"
    public let jsName = "DeviceState"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise)
    ]

    override public func load() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func thermalStateDidChange() {
        notifyListeners("thermalChange", data: ["thermal": Self.thermal(ProcessInfo.processInfo.thermalState)])
    }

    @objc func read(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(Self.state())
        }
    }

    /// The state now; battery monitoring is on for the read only (no polling, no timer).
    static func state() -> [String: Any] {
        let device = UIDevice.current
        let monitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = monitoring }
        let level = device.batteryLevel
        return [
            "thermal": thermal(ProcessInfo.processInfo.thermalState),
            // -1 when unknown (the simulator): null for the page.
            "battery": level < 0 ? NSNull() : Double(level),
            "charging": charging(device.batteryState),
            "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ]
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "critical"
        }
    }

    static func charging(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
