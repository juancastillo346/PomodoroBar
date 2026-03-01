import AppKit
import UserNotifications

private enum Constants {
    static let defaultIntervalSeconds = 10
    static let intervalSecondsKey = "intervalSeconds"
    static let customSoundPathKey = "customSoundPath"
}

final class TimerController {
    private var timer: Timer?
    private var startDate: Date?
    private(set) var isRunning = false
    private var tickHandler: (() -> Void)?
    var interval: TimeInterval = TimeInterval(Constants.defaultIntervalSeconds)

    func start(onTick: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()
        tickHandler = onTick
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.tickHandler?()
            // Schedule the next reminder only after the current one is handled.
            self.scheduleNextTick()
        }
        timer?.tolerance = 2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        tickHandler = nil
        isRunning = false
    }

    var elapsedText: String {
        guard isRunning else { return "Not running" }
        return "Running (\(formattedElapsed))"
    }

    var formattedElapsed: String {
        guard let startDate else { return "00:00:00" }
        let totalSeconds = Int(Date().timeIntervalSince(startDate))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let timerController = TimerController()
    private var uiRefreshTimer: Timer?

    private let statusMenu = NSMenu()
    private let stateItem = NSMenuItem(title: "Not running", action: nil, keyEquivalent: "")
    private lazy var setIntervalItem = NSMenuItem(
        title: "Set Interval...",
        action: #selector(setIntervalPrompt),
        keyEquivalent: ""
    )
    private lazy var presetItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
    private let presetMenu = NSMenu()
    private lazy var preset30MinItem = NSMenuItem(
        title: "30 Minutes",
        action: #selector(setPreset30Minutes),
        keyEquivalent: ""
    )
    private lazy var preset1HourItem = NSMenuItem(
        title: "1 Hour",
        action: #selector(setPreset1Hour),
        keyEquivalent: ""
    )
    private lazy var chooseSoundItem = NSMenuItem(
        title: "Choose Sound...",
        action: #selector(chooseCustomSound),
        keyEquivalent: ""
    )
    private lazy var resetSoundItem = NSMenuItem(
        title: "Use Default Sound",
        action: #selector(resetCustomSound),
        keyEquivalent: ""
    )
    private lazy var startItem = NSMenuItem(
        title: "Start",
        action: #selector(startTimer),
        keyEquivalent: "s"
    )
    private lazy var testNotificationItem = NSMenuItem(
        title: "Test Notification",
        action: #selector(testNotification),
        keyEquivalent: "t"
    )
    private lazy var stopItem = NSMenuItem(
        title: "Stop",
        action: #selector(stopTimer),
        keyEquivalent: "x"
    )
    
    private var intervalSeconds: Int {
        let saved = UserDefaults.standard.integer(forKey: Constants.intervalSecondsKey)
        return saved > 0 ? saved : Constants.defaultIntervalSeconds
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        timerController.interval = TimeInterval(intervalSeconds)
        configureNotifications()
        configureMenuBar()
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task { @MainActor in
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if granted {
                    sendSystemNotification(title: "PomodoroBar", body: "Notifications are enabled.")
                } else {
                    showNotificationPermissionHelp()
                }
            case .denied:
                showNotificationPermissionHelp()
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }

    private func configureMenuBar() {
        if let button = statusItem.button {
            button.title = intervalShortText(intervalSeconds)
            button.toolTip = "\(intervalDescription(intervalSeconds)) reminder timer"
        }

        startItem.target = self
        stopItem.target = self
        setIntervalItem.target = self
        preset30MinItem.target = self
        preset1HourItem.target = self
        chooseSoundItem.target = self
        resetSoundItem.target = self

        presetMenu.addItem(preset30MinItem)
        presetMenu.addItem(preset1HourItem)
        presetItem.submenu = presetMenu

        statusMenu.addItem(stateItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(presetItem)
        statusMenu.addItem(setIntervalItem)
        statusMenu.addItem(chooseSoundItem)
        statusMenu.addItem(resetSoundItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(startItem)
        statusMenu.addItem(stopItem)
        statusMenu.addItem(testNotificationItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q").target = self
        statusItem.menu = statusMenu

        refreshMenuState()
    }

    private func refreshMenuState() {
        stateItem.title = timerController.elapsedText
        statusItem.button?.title = timerController.isRunning ? timerController.formattedElapsed : intervalShortText(intervalSeconds)
        statusItem.button?.toolTip = "\(intervalDescription(intervalSeconds)) reminder timer"
        setIntervalItem.isEnabled = !timerController.isRunning
        preset30MinItem.isEnabled = !timerController.isRunning
        preset1HourItem.isEnabled = !timerController.isRunning
        startItem.isEnabled = !timerController.isRunning
        stopItem.isEnabled = timerController.isRunning
        testNotificationItem.isEnabled = true
        resetSoundItem.isEnabled = customSoundURL() != nil
    }

    @objc private func startTimer() {
        timerController.interval = TimeInterval(intervalSeconds)
        timerController.start { [weak self] in
            self?.sendReminderNotification()
            self?.refreshMenuState()
        }
        startUIRefreshTimer()
        refreshMenuState()
    }

    @objc private func stopTimer() {
        timerController.stop()
        stopUIRefreshTimer()
        refreshMenuState()
    }

    @objc private func testNotification() {
        sendSystemNotification(title: "PomodoroBar Test", body: "If you can see this, notifications are working.")
    }

    @objc private func setPreset30Minutes() {
        saveIntervalSeconds(30 * 60)
    }

    @objc private func setPreset1Hour() {
        saveIntervalSeconds(60 * 60)
    }

    @objc private func quitApp() {
        stopUIRefreshTimer()
        timerController.stop()
        NSApp.terminate(nil)
    }

    @objc private func chooseCustomSound() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a reminder sound"

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Constants.customSoundPathKey)
            refreshMenuState()
        }
    }

    @objc private func resetCustomSound() {
        UserDefaults.standard.removeObject(forKey: Constants.customSoundPathKey)
        refreshMenuState()
    }
    
    @objc private func setIntervalPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set timer interval"
        alert.informativeText = "Enter minutes and/or seconds."
        alert.alertStyle = .informational

        let total = intervalSeconds
        let currentMinutes = total / 60
        let currentSeconds = total % 60

        let minutesLabel = NSTextField(labelWithString: "Minutes")
        let minutesInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        minutesInput.placeholderString = "0"
        minutesInput.stringValue = "\(currentMinutes)"

        let secondsLabel = NSTextField(labelWithString: "Seconds")
        let secondsInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        secondsInput.placeholderString = "0"
        secondsInput.stringValue = "\(currentSeconds)"

        let minutesRow = NSStackView(views: [minutesLabel, minutesInput])
        minutesRow.orientation = .horizontal
        minutesRow.spacing = 8
        minutesRow.distribution = .fillProportionally

        let secondsRow = NSStackView(views: [secondsLabel, secondsInput])
        secondsRow.orientation = .horizontal
        secondsRow.spacing = 8
        secondsRow.distribution = .fillProportionally

        let container = NSStackView(views: [minutesRow, secondsRow])
        container.orientation = .vertical
        container.spacing = 8
        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let minutesValue = minutesInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondsValue = secondsInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(minutesValue) ?? -1
        let seconds = Int(secondsValue) ?? -1
        guard minutes >= 0, seconds >= 0 else {
            showInvalidIntervalAlert()
            return
        }
        let totalSeconds = (minutes * 60) + seconds
        guard totalSeconds > 0 else {
            showInvalidIntervalAlert()
            return
        }
        saveIntervalSeconds(totalSeconds)
    }

    private func startUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshMenuState()
        }
        uiRefreshTimer?.tolerance = 0.1
    }

    private func stopUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
    }

    private func sendReminderNotification() {
        playReminderSound()
        sendSystemNotification(
            title: "PomodoroBar",
            body: "\(intervalDescription(intervalSeconds)) have passed."
        )
    }

    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func showNotificationPermissionHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Notifications are disabled"
        alert.informativeText = "Enable notifications for PomodoroBar in System Settings to receive timer banners."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showInvalidIntervalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Invalid interval"
        alert.informativeText = "Please enter non-negative whole numbers, with at least one value greater than zero."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func intervalShortText(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return "\(minutes)m \(remainder)s"
        }
        return "\(seconds)s"
    }

    private func intervalDescription(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            let hours = seconds / 3600
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 min" : "\(minutes) mins"
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            let minutePart = minutes == 1 ? "1 min" : "\(minutes) mins"
            let secondPart = remainder == 1 ? "1 sec" : "\(remainder) secs"
            return "\(minutePart) \(secondPart)"
        }
        return seconds == 1 ? "1 sec" : "\(seconds) secs"
    }

    private func playReminderSound() {
        if let customURL = customSoundURL(),
           let customSound = NSSound(contentsOf: customURL, byReference: true) {
            customSound.play()
            return
        }

        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func customSoundURL() -> URL? {
        guard let customPath = UserDefaults.standard.string(forKey: Constants.customSoundPathKey),
              FileManager.default.fileExists(atPath: customPath) else {
            return nil
        }
        return URL(fileURLWithPath: customPath)
    }

    private func saveIntervalSeconds(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: Constants.intervalSecondsKey)
        timerController.interval = TimeInterval(seconds)
        refreshMenuState()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

@main
struct PomodoroBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
