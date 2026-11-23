import Foundation
import IOKit
import IOKit.ps
import Combine
import AppKit

// MARK: - Battery Manager (Hardware Care & Longevity)

@MainActor
public class BatteryManager: ObservableObject {
    public static let shared = BatteryManager()

    // MARK: - Published State
    @Published public var hasBattery: Bool = true
    @Published public var currentLevel: Int = 100
    @Published public var maxCapacityPercent: Int = 100
    @Published public var nominalCapacity: Int = 0
    @Published public var designCapacity: Int = 0
    @Published public var healthPercent: Int = 100
    @Published public var exactHealthPercent: Double = 100.0
    @Published public var cycleCount: Int = 0
    @Published public var temperature: Double = 0.0      // in °C
    @Published public var voltage: Double = 0.0          // in Volts
    @Published public var amperage: Int = 0              // in mA
    @Published public var wattage: Double = 0.0          // in Watts
    @Published public var isPluggedIn: Bool = false
    @Published public var isCharging: Bool = false
    @Published public var isFullyCharged: Bool = false
    @Published public var timeRemaining: Int = 0         // in minutes
    @Published public var isHelperInstalled: Bool = false
    @Published public var helperVersion: Int = 0
    @Published public var isInstallingHelper: Bool = false
    @Published public var statusMessage: String = "Đang kiểm tra..."
    @Published public var lastUpdated: Date = Date()

    // Extended Telemetry
    @Published public var adapterWatts: Int = 0          // e.g. 30W
    @Published public var adapterDescription: String = "" // e.g. "pd charger"
    @Published public var adapterSerial: String = ""
    @Published public var batterySerial: String = ""
    @Published public var gasGaugeChip: String = ""

    // User Settings (Stored in UserDefaults)
    @Published public var isTempAlertEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isTempAlertEnabled, forKey: "battery_temp_alert_enabled")
        }
    }

    @Published public var isSmartAlertsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSmartAlertsEnabled, forKey: "battery_smart_alerts_enabled")
        }
    }

    // Hardware Tab Selection (0: Nguồn & Pin, 1: Sleep Guard, 2: Đóng băng CPU)
    @Published public var selectedHardwareTab: Int = 0

    // Sleep Guard Settings & State
    @Published public var isSleepGuardEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSleepGuardEnabled, forKey: "battery_sleep_guard_enabled")
        }
    }

    @Published public var sleepGuardTurnOffBluetooth: Bool = true {
        didSet {
            UserDefaults.standard.set(sleepGuardTurnOffBluetooth, forKey: "battery_sleep_guard_bt")
        }
    }

    @Published public var lastSleepReport: String = ""

    private var sleepDate: Date? = nil
    private var sleepBatteryLevel: Int = 0
    private var wasBluetoothTurnedOffBySleepGuard: Bool = false

    public var tempAlertThreshold: Double = 38.0 // Warning at 38°C
    private var lastTempAlertDate: Date? = nil
    private var lastExtDisplayAlertDate: Date? = nil
    private var lastLowBatteryAlertLevel: Int? = nil

    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var isPopoverVisible: Bool = false
    private var powerSourceRunLoopSource: CFRunLoopSource?

    private init() {
        // Load preferences
        if UserDefaults.standard.object(forKey: "battery_temp_alert_enabled") != nil {
            self.isTempAlertEnabled = UserDefaults.standard.bool(forKey: "battery_temp_alert_enabled")
        } else {
            self.isTempAlertEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_smart_alerts_enabled") != nil {
            self.isSmartAlertsEnabled = UserDefaults.standard.bool(forKey: "battery_smart_alerts_enabled")
        } else {
            self.isSmartAlertsEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_enabled") != nil {
            self.isSleepGuardEnabled = UserDefaults.standard.bool(forKey: "battery_sleep_guard_enabled")
        } else {
            self.isSleepGuardEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_bt") != nil {
            self.sleepGuardTurnOffBluetooth = UserDefaults.standard.bool(forKey: "battery_sleep_guard_bt")
        } else {
            self.sleepGuardTurnOffBluetooth = true
        }

        self.lastSleepReport = UserDefaults.standard.string(forKey: "battery_last_sleep_report") ?? ""

        // Setup Sleep & Real-Time IOPowerSources Observers
        setupSleepObservers()
        setupPowerSourceNotifications()

        // Initial check
        checkHelperStatus()
        refreshBatteryInfo()

        // Start background polling timer
        startPolling()
    }

    deinit {
        timer?.invalidate()
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Real-Time Hardware Power Notifications & App Nap Prevention

    private func setupPowerSourceNotifications() {
        let callback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in
                let bm = BatteryManager.shared
                bm.refreshBatteryInfo()
                bm.syncPollingTimer()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            self.powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Sleep Guard Lifecycle

    private func setupSleepObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        // Sleep Guard Bluetooth & drain tracking
        guard isSleepGuardEnabled else { return }
        self.sleepDate = Date()
        self.sleepBatteryLevel = self.currentLevel

        // Turn off Bluetooth if configured to prevent phantom Dark Wake drain
        if sleepGuardTurnOffBluetooth && BluetoothManager.shared.isAvailable && BluetoothManager.shared.isPowerOn {
            self.wasBluetoothTurnedOffBySleepGuard = true
            BluetoothManager.shared.isPowerOn = false
        }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        refreshBatteryInfo()

        // Sleep Guard Bluetooth restoration & report
        guard isSleepGuardEnabled else { return }

        // Restore Bluetooth if previously turned off by Sleep Guard
        if wasBluetoothTurnedOffBySleepGuard && BluetoothManager.shared.isAvailable {
            BluetoothManager.shared.isPowerOn = true
            wasBluetoothTurnedOffBySleepGuard = false
        }

        // Calculate sleep duration & battery delta
        if let sDate = sleepDate {
            let elapsed = Date().timeIntervalSince(sDate)
            let hours = Int(elapsed) / 3600
            let mins = (Int(elapsed) % 3600) / 60
            let delta = currentLevel - sleepBatteryLevel

            let drainText: String
            if delta >= 0 {
                drainText = "Hao pin: 0% (Hoàn hảo)"
            } else {
                drainText = "Hao pin: \(abs(delta))% (\(sleepBatteryLevel)% ➔ \(currentLevel)%)"
            }

            let report = "Gập máy \(hours)h\(mins)m • \(drainText)"
            self.lastSleepReport = report
            UserDefaults.standard.set(report, forKey: "battery_last_sleep_report")

            if isSmartAlertsEnabled {
                sendNotification(
                    title: "Sleep Guard: Báo cáo khi mở máy",
                    body: "Máy đã nghỉ \(hours)h\(mins)m. \(drainText)."
                )
            }
            self.sleepDate = nil
        }
    }

    // MARK: - Polling Timer (Dynamic & Energy-Aware)

    public func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible {
            refreshBatteryInfo()
        }
        syncPollingTimer()
    }

    public func startPolling() {
        syncPollingTimer()
    }

    private func syncPollingTimer() {
        let desiredInterval: TimeInterval
        if !hasBattery {
            desiredInterval = 0
        } else if isPopoverVisible {
            desiredInterval = 3.5
        } else {
            // Popover đóng: 0 timer wakeup, dựa hoàn toàn vào IOPSNotification + didWake.
            desiredInterval = 0
        }

        if desiredInterval <= 0 {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            return
        }

        guard timer == nil || timerInterval != desiredInterval else { return }
        timer?.invalidate()
        timerInterval = desiredInterval
        let t = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshBatteryInfo()
                self.syncPollingTimer()
            }
        }
        t.tolerance = desiredInterval >= 15.0 ? 4.0 : 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func setIfChanged<T: Equatable>(_ target: inout T, _ newValue: T) {
        if target != newValue {
            target = newValue
        }
    }

    // MARK: - IOKit Battery Status Query

    public func refreshBatteryInfo() {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            // Desktop Macs (Mac mini, Mac Studio Max/Ultra, iMac, Mac Pro) do not have an internal battery
            setIfChanged(&self.hasBattery, false)
            setIfChanged(&self.isPluggedIn, true)
            setIfChanged(&self.isCharging, false)
            setIfChanged(&self.isFullyCharged, true)
            setIfChanged(&self.currentLevel, 100)
            setIfChanged(&self.statusMessage, tr("Nguồn AC trực tiếp (Máy bàn Mac)", "Direct AC Power (Desktop Mac)"))
            syncPollingTimer()
            return
        }
        defer { IOObjectRelease(service) }
        setIfChanged(&self.hasBattery, true)

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }

        setIfChanged(&self.currentLevel, dict["CurrentCapacity"] as? Int ?? self.currentLevel)
        setIfChanged(&self.maxCapacityPercent, dict["MaxCapacity"] as? Int ?? 100)
        setIfChanged(&self.nominalCapacity, dict["NominalChargeCapacity"] as? Int ?? self.nominalCapacity)
        setIfChanged(&self.designCapacity, dict["DesignCapacity"] as? Int ?? self.designCapacity)
        setIfChanged(&self.cycleCount, dict["CycleCount"] as? Int ?? self.cycleCount)
        let rawCharging = dict["IsCharging"] as? Bool ?? false
        setIfChanged(&self.isPluggedIn, dict["ExternalConnected"] as? Bool ?? false)
        setIfChanged(&self.isFullyCharged, dict["FullyCharged"] as? Bool ?? false)
        setIfChanged(&self.timeRemaining, dict["TimeRemaining"] as? Int ?? 0)

        if let rawTemp = dict["Temperature"] as? Double {
            let t = rawTemp / 100.0
            if abs(self.temperature - t) >= 0.05 { self.temperature = t }
        } else if let rawTempInt = dict["Temperature"] as? Int {
            let t = Double(rawTempInt) / 100.0
            if abs(self.temperature - t) >= 0.05 { self.temperature = t }
        }

        if let rawVolt = dict["Voltage"] as? Double {
            let v = rawVolt / 1000.0
            if abs(self.voltage - v) >= 0.01 { self.voltage = v }
        } else if let rawVoltInt = dict["Voltage"] as? Int {
            let v = Double(rawVoltInt) / 1000.0
            if abs(self.voltage - v) >= 0.01 { self.voltage = v }
        }

        if let rawAmp = dict["Amperage"] as? Int64 {
            // Signed 64-bit: negative = discharging, positive = charging, 0 = bypass
            setIfChanged(&self.amperage, Int(rawAmp))
        }

        // Live Wattage = Voltage (V) * abs(Amperage (A))
        let newWattage = (self.voltage * Double(abs(self.amperage))) / 1000.0
        if abs(self.wattage - newWattage) >= 0.05 {
            self.wattage = newWattage
        }

        // Responsive charging detection: even if macOS IsCharging flag is delayed, positive current means charging
        let nextCharging = rawCharging || (self.isPluggedIn && self.amperage > 50)
        setIfChanged(&self.isCharging, nextCharging)

        // Parse Adapter details (only valid when plugged in)
        if self.isPluggedIn {
            if let adapter = dict["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? Int, w > 0 {
                setIfChanged(&self.adapterWatts, w)
                setIfChanged(&self.adapterDescription, adapter["Description"] as? String ?? "USB-C PD")
                setIfChanged(&self.adapterSerial, adapter["SerialString"] as? String ?? "")
            } else if let adapterList = dict["AppleRawAdapterDetails"] as? [[String: Any]],
                      let first = adapterList.first,
                      let w = first["Watts"] as? Int, w > 0 {
                setIfChanged(&self.adapterWatts, w)
                setIfChanged(&self.adapterDescription, first["Description"] as? String ?? "USB-C PD")
                setIfChanged(&self.adapterSerial, first["SerialString"] as? String ?? "")
            }
        } else {
            setIfChanged(&self.adapterWatts, 0)
            setIfChanged(&self.adapterDescription, "")
            setIfChanged(&self.adapterSerial, "")
        }

        setIfChanged(&self.batterySerial, dict["Serial"] as? String ?? self.batterySerial)
        setIfChanged(&self.gasGaugeChip, dict["DeviceName"] as? String ?? self.gasGaugeChip)

        if self.designCapacity > 0 && self.nominalCapacity > 0 {
            let ratio = Double(self.nominalCapacity) / Double(self.designCapacity) * 100.0
            if abs(self.exactHealthPercent - ratio) >= 0.01 {
                self.exactHealthPercent = ratio
            }
            setIfChanged(&self.healthPercent, min(100, Int(round(ratio))))
        }

        if isPopoverVisible {
            self.lastUpdated = Date()
        }
        let status: String
        if !isPluggedIn {
            status = tr("Đang dùng pin (\(currentLevel)%)", "On battery (\(currentLevel)%)")
        } else if isCharging {
            status = tr("Đang sạc (\(currentLevel)%)", "Charging (\(currentLevel)%)")
        } else if isFullyCharged || currentLevel >= 100 {
            status = tr("Đã sạc đầy 100%", "Fully charged 100%")
        } else {
            status = tr("Đã cắm sạc, đang giữ \(currentLevel)% (giới hạn sạc của macOS)", "Plugged in, holding \(currentLevel)% (macOS charge limit)")
        }
        setIfChanged(&statusMessage, status)

        checkTemperatureAlert()
        checkSmartSafetyAlerts()
    }

    // MARK: - Smart Safety & Anti-Wear Alerts

    private func checkSmartSafetyAlerts() {
        guard isSmartAlertsEnabled && hasBattery else { return }

        // 1. Alert: External display active but running on battery (not plugged in)
        let hasExtDisplay = DisplayManager.shared.monitors.contains(where: { !$0.isBuiltIn && $0.isConnected })
        if hasExtDisplay && !isPluggedIn {
            let now = Date()
            if lastExtDisplayAlertDate == nil || now.timeIntervalSince(lastExtDisplayAlertDate!) > 900 { // 15 mins
                lastExtDisplayAlertDate = now
                sendNotification(
                    title: "Đang dùng màn ngoài nhưng chưa cắm sạc!",
                    body: "Màn hình ngoài đang làm GPU xả pin rất nặng và nóng máy. Hãy cắm sạc để máy chạy điện trực tiếp và bảo vệ pin!"
                )
            }
        } else if isPluggedIn {
            lastExtDisplayAlertDate = nil
        }

        // 2. Alert: Low battery warning to prevent deep discharge (<20% and <10%)
        if !isPluggedIn {
            if currentLevel <= 10 {
                if lastLowBatteryAlertLevel != 10 {
                    lastLowBatteryAlertLevel = 10
                    sendNotification(
                        title: "🚨 KHẨN CẤP: Pin còn 10%!",
                        body: "Tuyệt đối không để máy dùng cạn đáy sập nguồn (gây hại cell pin vĩnh viễn). Hãy cắm sạc ngay!"
                    )
                }
            } else if currentLevel <= 20 {
                if lastLowBatteryAlertLevel != 20 {
                    lastLowBatteryAlertLevel = 20
                    sendNotification(
                        title: "Pin yếu (20%) - Hãy cắm sạc!",
                        body: "Để tránh hiện tượng tụt áp sâu (Deep Discharge) làm chai pin, hãy cắm sạc ngay bây giờ."
                    )
                }
            } else {
                lastLowBatteryAlertLevel = nil
            }
        } else {
            lastLowBatteryAlertLevel = nil
        }

    }

    // MARK: - Temperature Safety Alerts

    private func checkTemperatureAlert() {
        guard isTempAlertEnabled && temperature >= tempAlertThreshold else { return }

        let now = Date()
        if let last = lastTempAlertDate, now.timeIntervalSince(last) < 600 {
            return // Wait at least 10 minutes between alerts
        }
        lastTempAlertDate = now

        let tempStr = String(format: "%.1f°C", temperature)
        sendNotification(
            title: "Cảnh báo nhiệt độ pin (\(tempStr))",
            body: "Nhiệt độ pin MacBook đã lên tới \(tempStr)! Hãy kê thoáng máy hoặc mở phần Giám sát năng lượng để đóng băng các tác vụ nặng."
        )
    }

    private func sendNotification(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"Submarine\""
        DispatchQueue.global(qos: .utility).async {
            _ = shell("osascript -e '\(script)'")
        }
    }

    // MARK: - Helper Installation Check & Prompt

    public func checkHelperStatus(completion: ((Bool) -> Void)? = nil) {
        let exists = FileManager.default.fileExists(atPath: PrivilegedHelper.powerPath)
        guard exists else {
            let hasLegacy = FileManager.default.fileExists(atPath: PrivilegedHelper.legacyPowerPath)
            self.isHelperInstalled = false
            self.helperVersion = hasLegacy ? 2 : 0
            completion?(false)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let (out, code) = shell(PrivilegedHelper.sudo("version 2>&1"))
            var ver = 0
            if code == 0, let r = out.range(of: "HELPER_VERSION:") {
                ver = Int(out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: { $0.isNumber })) ?? 0
            }
            // Không còn dùng helper cũ (<= v2 ở /usr/local/bin với sudoers mở cho mọi user);
            // người dùng cài lại 1 lần lên v3 trong /Library/PrivilegedHelperTools, bộ cài tự gỡ bản cũ.
            let isRealReady = (ver >= PrivilegedHelper.requiredVersion)
            DispatchQueue.main.async {
                self.helperVersion = ver
                self.isHelperInstalled = isRealReady
                completion?(isRealReady)
            }
        }
    }

    public func installHelper(completion: ((Bool) -> Void)? = nil) {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Chỉ lấy tệp nguồn từ app bundle (hoặc /Applications/HyperMac.app), tuyệt đối không lấy từ thư mục làm việc hiện tại.
            let searchDirs = [
                Bundle.main.resourcePath,
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").path,
                "/Applications/HyperMac.app/Contents/Resources"
            ].compactMap { $0 }

            var smcSrc: String? = Bundle.main.path(forResource: "smc", ofType: nil)
            var helperSrc: String? = Bundle.main.path(forResource: "displaycontrol-power", ofType: nil)
            var installScript: String? = Bundle.main.path(forResource: "install-helper", ofType: "sh")

            for dir in searchDirs {
                if smcSrc == nil {
                    let path = (dir as NSString).appendingPathComponent("smc")
                    if FileManager.default.fileExists(atPath: path) { smcSrc = path }
                }
                if helperSrc == nil {
                    let path = (dir as NSString).appendingPathComponent("displaycontrol-power")
                    if FileManager.default.fileExists(atPath: path) { helperSrc = path }
                }
                if installScript == nil {
                    let path = (dir as NSString).appendingPathComponent("install-helper.sh")
                    if FileManager.default.fileExists(atPath: path) { installScript = path }
                }
            }

            guard let sSMC = smcSrc, let sHelper = helperSrc, let sInstall = installScript else {
                appLog("❌ installHelper: missing resource paths (smc: \(smcSrc ?? "nil"), helper: \(helperSrc ?? "nil"), script: \(installScript ?? "nil"))")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            // Kiểm tra tên user chặt chẽ trước khi ghi rule sudoers
            let user = NSUserName()
            guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
                  !user.hasPrefix("-"), user != ".", user != "..", user != "ALL", user != "root"
            else {
                appLog("❌ installHelper: unsafe user name")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            // Stage bản sao sạch vào thư mục riêng tư (0700) trong /private/tmp để tránh lỗi TCC khi app chạy từ ~/Downloads hoặc ~/Documents
            let fm = FileManager.default
            let stageURL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("hypermac-helper-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: stageURL) }

            let stagedSMC = stageURL.appendingPathComponent("smc").path
            let stagedHelper = stageURL.appendingPathComponent("displaycontrol-power").path
            let stagedInstall = stageURL.appendingPathComponent("install-helper.sh").path

            do {
                try fm.createDirectory(at: stageURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try fm.copyItem(atPath: sSMC, toPath: stagedSMC)
                try fm.copyItem(atPath: sHelper, toPath: stagedHelper)
                try fm.copyItem(atPath: sInstall, toPath: stagedInstall)
            } catch {
                appLog("❌ installHelper: failed staging resources: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            let stagedPaths = [stagedInstall, stagedSMC, stagedHelper]
            guard !stagedPaths.contains(where: { $0.contains("'") || $0.contains("\\") || $0.contains("\"") }) else {
                appLog("❌ installHelper: unsafe staged path")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            let appleScriptCmd = """
            do shell script "/bin/bash '\(stagedInstall)' '\(stagedSMC)' '\(stagedHelper)' '\(user)'" with administrator privileges
            """

            var errorDict: NSDictionary?
            if let scriptObj = NSAppleScript(source: appleScriptCmd) {
                _ = scriptObj.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    appLog("⚠️ installHelper AppleScript error: \(err)")
                }
            }

            // Verify installation with deep probe
            let (out, code) = shell(PrivilegedHelper.sudo("version 2>&1"))
            var ver = 0
            if code == 0, let r = out.range(of: "HELPER_VERSION:") {
                ver = Int(out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: { $0.isNumber })) ?? 0
            }
            let success = (code == 0 && ver >= PrivilegedHelper.requiredVersion)

            DispatchQueue.main.async {
                self.isInstallingHelper = false
                self.helperVersion = ver
                self.isHelperInstalled = success
                FanManager.shared.checkHelper()
                completion?(success)
            }
        }
    }
}
